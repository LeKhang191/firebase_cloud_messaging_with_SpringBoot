package com.seminar.fcm;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.*;
import com.seminar.fcm.entity.DeviceToken;
import com.seminar.fcm.repository.DeviceTokenRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyList;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.*;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.*;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * Autotest toàn bộ flow: đăng ký thiết bị -> gửi thông báo (token / user / broadcast / topic / order)
 * -> dọn token chết.
 *
 * FirebaseMessaging được MOCK nên KHÔNG cần file firebase-service-account.json và KHÔNG gửi thật tới FCM.
 * DB dùng H2 in-memory.
 *
 * Chạy:  mvn test   (hoặc  mvn -Dtest=FcmFlowTest test)
 */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:fcmtest;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "firebase.credentials-path=classpath:/not-used.json"
})
@AutoConfigureMockMvc
class FcmFlowTest {

    @Autowired MockMvc mvc;
    @Autowired ObjectMapper json;
    @Autowired DeviceTokenRepository repo;

    // Thay 2 bean Firebase bằng mock -> FirebaseConfig không đọc credentials
    @MockBean FirebaseApp firebaseApp;
    @MockBean FirebaseMessaging messaging;

    @BeforeEach
    void cleanDb() {
        repo.deleteAll();
    }

    // ------------------------------------------------------------------ helpers

    private ResultActions postJson(String url, Object body) throws Exception {
        return mvc.perform(post(url).contentType(MediaType.APPLICATION_JSON).content(json.writeValueAsString(body)));
    }

    private void register(String userId, String token, String platform) throws Exception {
        Map<String, Object> body = new java.util.HashMap<>();
        body.put("userId", userId);
        body.put("token", token);
        if (platform != null) body.put("platform", platform);
        postJson("/api/devices/register", body).andExpect(status().isOk());
    }

    /** Stub sendEachForMulticast. Tham so da duoc tao xong truoc khi vao ham -> khong long stubbing. */
    private void givenMulticast(BatchResponse response) throws Exception {
        when(messaging.sendEachForMulticast(any(MulticastMessage.class))).thenReturn(response);
    }

    /** Stub messaging.send() nem FirebaseMessagingException voi ma loi cho truoc. */
    private void givenSendThrows(MessagingErrorCode code) throws Exception {
        FirebaseMessagingException ex = fcmException(code);
        when(messaging.send(any(Message.class))).thenThrow(ex);
    }

    private static Map<String, Object> payload(String title, String body) {
        return Map.of("title", title, "body", body);
    }

    private static SendResponse ok() {
        SendResponse r = mock(SendResponse.class);
        when(r.isSuccessful()).thenReturn(true);
        return r;
    }

    private static SendResponse fail(MessagingErrorCode code) {
        FirebaseMessagingException ex = fcmException(code);
        SendResponse r = mock(SendResponse.class);
        when(r.isSuccessful()).thenReturn(false);
        when(r.getException()).thenReturn(ex);
        return r;
    }

    private static FirebaseMessagingException fcmException(MessagingErrorCode code) {
        FirebaseMessagingException ex = mock(FirebaseMessagingException.class);
        when(ex.getMessagingErrorCode()).thenReturn(code);
        when(ex.getMessage()).thenReturn("mock error " + code);
        return ex;
    }

    private static BatchResponse batch(SendResponse... responses) {
        List<SendResponse> list = List.of(responses);
        long okCount = list.stream().filter(SendResponse::isSuccessful).count();
        BatchResponse b = mock(BatchResponse.class);
        when(b.getResponses()).thenReturn(list);
        when(b.getSuccessCount()).thenReturn((int) okCount);
        when(b.getFailureCount()).thenReturn(list.size() - (int) okCount);
        return b;
    }

    // ------------------------------------------------------------------ 1. Device registration

    @Test
    @DisplayName("Đăng ký thiết bị: platform mặc định = web, lưu vào DB")
    void registerDevice_defaultsPlatformToWeb() throws Exception {
        postJson("/api/devices/register", Map.of("userId", "u1", "token", "tokenAAA"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId").value("u1"))
                .andExpect(jsonPath("$.platform").value("web"))
                .andExpect(jsonPath("$.id").isNumber());

        assertEquals(1, repo.count());
    }

    @Test
    @DisplayName("Đăng ký lại cùng token: upsert (không tạo bản ghi mới), đổi chủ + platform")
    void registerDevice_sameToken_isUpsert() throws Exception {
        register("u1", "tokenAAA", "web");
        register("u2", "tokenAAA", "android");

        assertEquals(1, repo.count());
        DeviceToken d = repo.findByToken("tokenAAA").orElseThrow();
        assertEquals("u2", d.getUserId());
        assertEquals("android", d.getPlatform());
    }

    @Test
    @DisplayName("Đăng ký thiếu userId/token -> 400 VALIDATION_FAILED")
    void registerDevice_validation() throws Exception {
        postJson("/api/devices/register", Map.of("userId", "", "token", ""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"))
                .andExpect(jsonPath("$.fields.userId").exists())
                .andExpect(jsonPath("$.fields.token").exists());

        assertEquals(0, repo.count());
    }

    @Test
    @DisplayName("List thiết bị theo user: token bị cắt còn 20 ký tự + '...'")
    void listDevicesByUser_masksToken() throws Exception {
        String longToken = "abcdefghijklmnopqrstuvwxyz0123456789";
        register("u1", longToken, "web");
        register("u2", "other-user-token", "web");

        mvc.perform(get("/api/devices/user/u1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].tokenPreview").value("abcdefghijklmnopqrst..."))
                .andExpect(jsonPath("$[0].platform").value("web"));
    }

    @Test
    @DisplayName("Hủy đăng ký thiết bị theo token")
    void unregisterDevice() throws Exception {
        register("u1", "tokenAAA", "web");

        mvc.perform(delete("/api/devices").param("token", "tokenAAA"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("unregistered"));

        assertEquals(0, repo.count());
    }

    // ------------------------------------------------------------------ 2. Gửi tới 1 token

    @Test
    @DisplayName("Gửi tới 1 token thành công -> trả messageId")
    void sendToToken_success() throws Exception {
        when(messaging.send(any(Message.class))).thenReturn("projects/x/messages/123");

        postJson("/api/notifications/token", Map.of("token", "tokenAAA", "payload", payload("Hi", "Hello")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messageId").value("projects/x/messages/123"));

        verify(messaging).send(any(Message.class));
    }

    @Test
    @DisplayName("Gửi tới token thiếu title -> 400, không gọi FCM")
    void sendToToken_validation() throws Exception {
        postJson("/api/notifications/token", Map.of("token", "tokenAAA", "payload", Map.of("body", "no title")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"));

        verifyNoInteractions(messaging);
    }

    @Test
    @DisplayName("FCM trả UNREGISTERED -> 502 FCM_ERROR và token bị xóa khỏi DB")
    void sendToToken_unregistered_removesToken() throws Exception {
        register("u1", "deadToken", "web");
        givenSendThrows(MessagingErrorCode.UNREGISTERED);

        postJson("/api/notifications/token", Map.of("token", "deadToken", "payload", payload("Hi", "Hello")))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.error").value("FCM_ERROR"))
                .andExpect(jsonPath("$.code").value("UNREGISTERED"));

        assertTrue(repo.findByToken("deadToken").isEmpty(), "token chết phải bị xóa");
    }

    @Test
    @DisplayName("FCM lỗi khác (INTERNAL) -> 502 nhưng GIỮ token trong DB")
    void sendToToken_otherError_keepsToken() throws Exception {
        register("u1", "goodToken", "web");
        givenSendThrows(MessagingErrorCode.INTERNAL);

        postJson("/api/notifications/token", Map.of("token", "goodToken", "payload", payload("Hi", "Hello")))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.code").value("INTERNAL"));

        assertTrue(repo.findByToken("goodToken").isPresent());
    }

    // ------------------------------------------------------------------ 3. Gửi tới user (multicast)

    @Test
    @DisplayName("Gửi tới user có 3 thiết bị, 1 token chết -> success=2, failure=1, token chết bị dọn")
    void sendToUser_cleansDeadTokens() throws Exception {
        register("u1", "t1", "web");
        register("u1", "t2-dead", "android");
        register("u1", "t3", "ios");
        register("u2", "t-other", "web");

        givenMulticast(batch(ok(), fail(MessagingErrorCode.UNREGISTERED), ok()));

        postJson("/api/notifications/user/u1", payload("Hi", "Hello"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(2))
                .andExpect(jsonPath("$.failureCount").value(1))
                .andExpect(jsonPath("$.removedInvalidTokens.length()").value(1))
                .andExpect(jsonPath("$.removedInvalidTokens[0]").value("t2-dead"))
                .andExpect(jsonPath("$.errors.length()").value(1));

        assertTrue(repo.findByToken("t2-dead").isEmpty());
        assertEquals(3, repo.count());   // t1, t3, t-other còn lại
    }

    @Test
    @DisplayName("Lỗi không phải UNREGISTERED (QUOTA_EXCEEDED): tính failure nhưng KHÔNG xóa token")
    void sendToUser_nonFatalFailure_keepsToken() throws Exception {
        register("u1", "t1", "web");
        givenMulticast(batch(fail(MessagingErrorCode.QUOTA_EXCEEDED)));

        postJson("/api/notifications/user/u1", payload("Hi", "Hello"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(0))
                .andExpect(jsonPath("$.failureCount").value(1))
                .andExpect(jsonPath("$.removedInvalidTokens.length()").value(0));

        assertEquals(1, repo.count());
    }

    @Test
    @DisplayName("User chưa có thiết bị nào -> 0/0 và không gọi FCM")
    void sendToUser_noDevices() throws Exception {
        postJson("/api/notifications/user/ghost", payload("Hi", "Hello"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(0))
                .andExpect(jsonPath("$.failureCount").value(0));

        verifyNoInteractions(messaging);
    }

    // ------------------------------------------------------------------ 4. Broadcast

    @Test
    @DisplayName("Broadcast tới thiết bị của nhiều user, dọn token chết")
    void broadcast_allUsers() throws Exception {
        register("u1", "t1", "web");
        register("u2", "t2-dead", "web");
        register("u3", "t3", "web");

        givenMulticast(batch(ok(), fail(MessagingErrorCode.UNREGISTERED), ok()));

        postJson("/api/notifications/broadcast", payload("Sale", "50% off"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(2))
                .andExpect(jsonPath("$.failureCount").value(1))
                .andExpect(jsonPath("$.removedInvalidTokens[0]").value("t2-dead"));

        assertEquals(2, repo.count());
    }

    @Test
    @DisplayName("1001 token -> chia thành 3 lô (500 + 500 + 1)")
    void broadcast_batchesBy500() throws Exception {
        List<DeviceToken> devices = new ArrayList<>();
        for (int i = 0; i < 1001; i++) {
            DeviceToken d = new DeviceToken();
            d.setUserId("bulk-user");
            d.setToken("bulk-token-" + i);
            d.setPlatform("web");
            devices.add(d);
        }
        repo.saveAll(devices);

        givenMulticast(batch());

        postJson("/api/notifications/broadcast", payload("Hi", "Hello")).andExpect(status().isOk());

        verify(messaging, times(3)).sendEachForMulticast(any(MulticastMessage.class));
    }

    // ------------------------------------------------------------------ 5. Topic

    @Test
    @DisplayName("Subscribe -> gửi topic -> unsubscribe")
    void topicFlow() throws Exception {
        TopicManagementResponse sub = mock(TopicManagementResponse.class);
        when(sub.getSuccessCount()).thenReturn(1);
        when(sub.getFailureCount()).thenReturn(0);
        when(messaging.subscribeToTopic(anyList(), eq("news"))).thenReturn(sub);
        when(messaging.unsubscribeFromTopic(anyList(), eq("news"))).thenReturn(sub);
        when(messaging.send(any(Message.class))).thenReturn("topic-msg-1");

        postJson("/api/topics/subscribe", Map.of("token", "tokenAAA", "topic", "news"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(1))
                .andExpect(jsonPath("$.failureCount").value(0));

        postJson("/api/notifications/topic/news", payload("Breaking", "News!"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messageId").value("topic-msg-1"));

        postJson("/api/topics/unsubscribe", Map.of("token", "tokenAAA", "topic", "news"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(1));

        verify(messaging).subscribeToTopic(List.of("tokenAAA"), "news");
        verify(messaging).unsubscribeFromTopic(List.of("tokenAAA"), "news");
    }

    @Test
    @DisplayName("Topic có ký tự không hợp lệ -> 400, không gọi FCM")
    void subscribe_invalidTopicName() throws Exception {
        postJson("/api/topics/subscribe", Map.of("token", "tokenAAA", "topic", "bad topic!"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"))
                .andExpect(jsonPath("$.fields.topic").exists());

        verifyNoInteractions(messaging);
    }

    // ------------------------------------------------------------------ 6. Order demo

    @Test
    @DisplayName("Cập nhật trạng thái đơn hàng -> gửi push tới mọi thiết bị của user")
    void orderStatus_sendsToUserDevices() throws Exception {
        register("u1", "t1", "web");
        register("u1", "t2", "android");
        givenMulticast(batch(ok(), ok()));

        for (String st : List.of("CONFIRMED", "SHIPPING", "DELIVERED", "CANCELLED")) {
            postJson("/api/orders/1001/status", Map.of("userId", "u1", "status", st))
                    .andExpect(status().isOk())
                    .andExpect(jsonPath("$.successCount").value(2))
                    .andExpect(jsonPath("$.failureCount").value(0));
        }

        verify(messaging, times(4)).sendEachForMulticast(any(MulticastMessage.class));
    }

    @Test
    @DisplayName("Order status sai giá trị / thiếu userId -> 400")
    void orderStatus_validation() throws Exception {
        postJson("/api/orders/1001/status", Map.of("userId", "u1", "status", "FLYING"))
                .andExpect(status().isBadRequest());

        postJson("/api/orders/1001/status", Map.of("status", "SHIPPING"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"))
                .andExpect(jsonPath("$.fields.userId").exists());

        verifyNoInteractions(messaging);
    }

    // ------------------------------------------------------------------ 7. Full flow end-to-end

    @Test
    @DisplayName("FULL FLOW: register 2 thiết bị -> đơn SHIPPING (1 token chết bị dọn) -> đơn DELIVERED chỉ còn 1 token")
    void fullFlow_registerThenOrderThenSelfCleaning() throws Exception {
        // 1. user đăng ký 2 thiết bị
        register("alice", "phone-token", "android");
        register("alice", "laptop-token-dead", "web");
        mvc.perform(get("/api/devices/user/alice"))
                .andExpect(jsonPath("$.length()").value(2));

        // 2. đơn chuyển SHIPPING: laptop đã gỡ app -> UNREGISTERED
        givenMulticast(batch(ok(), fail(MessagingErrorCode.UNREGISTERED)));

        postJson("/api/orders/2002/status", Map.of("userId", "alice", "status", "SHIPPING"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(1))
                .andExpect(jsonPath("$.failureCount").value(1))
                .andExpect(jsonPath("$.removedInvalidTokens[0]").value("laptop-token-dead"));

        // 3. token chết đã bị dọn tự động
        mvc.perform(get("/api/devices/user/alice"))
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].platform").value("android"));

        // 4. đơn DELIVERED: lần này chỉ còn 1 thiết bị
        givenMulticast(batch(ok()));

        postJson("/api/orders/2002/status", Map.of("userId", "alice", "status", "DELIVERED"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(1))
                .andExpect(jsonPath("$.failureCount").value(0))
                .andExpect(jsonPath("$.removedInvalidTokens.length()").value(0));

        // 5. user logout -> hủy đăng ký -> không còn thiết bị để gửi
        mvc.perform(delete("/api/devices").param("token", "phone-token")).andExpect(status().isOk());
        assertEquals(0, repo.count());
    }
}
