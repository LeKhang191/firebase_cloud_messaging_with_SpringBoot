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
 * Autotest for the whole flow: device registration -> send notifications (token / user / broadcast / topic / order)
 * -> dead token cleanup.
 *
 * FirebaseMessaging is MOCKED: no firebase-service-account.json is needed and nothing is sent to FCM.
 * The database is in-memory H2.
 *
 * Run:  mvn test   (or  mvn -Dtest=FcmFlowTest test)
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

    // Replace the two Firebase beans with mocks so FirebaseConfig does not read credentials
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

    /** Stubs sendEachForMulticast. The argument is fully built before the call, so stubbing is not nested. */
    private void givenMulticast(BatchResponse response) throws Exception {
        when(messaging.sendEachForMulticast(any(MulticastMessage.class))).thenReturn(response);
    }

    /** Stubs messaging.send() to throw a FirebaseMessagingException with the given error code. */
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
    @DisplayName("Register device: default platform = web, saved to DB")
    void registerDevice_defaultsPlatformToWeb() throws Exception {
        postJson("/api/devices/register", Map.of("userId", "u1", "token", "tokenAAA"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.userId").value("u1"))
                .andExpect(jsonPath("$.platform").value("web"))
                .andExpect(jsonPath("$.id").isNumber());

        assertEquals(1, repo.count());
    }

    @Test
    @DisplayName("Re-register same token: upsert (no new row), owner and platform updated")
    void registerDevice_sameToken_isUpsert() throws Exception {
        register("u1", "tokenAAA", "web");
        register("u2", "tokenAAA", "android");

        assertEquals(1, repo.count());
        DeviceToken d = repo.findByToken("tokenAAA").orElseThrow();
        assertEquals("u2", d.getUserId());
        assertEquals("android", d.getPlatform());
    }

    @Test
    @DisplayName("Register without userId/token -> 400 VALIDATION_FAILED")
    void registerDevice_validation() throws Exception {
        postJson("/api/devices/register", Map.of("userId", "", "token", ""))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"))
                .andExpect(jsonPath("$.fields.userId").exists())
                .andExpect(jsonPath("$.fields.token").exists());

        assertEquals(0, repo.count());
    }

    @Test
    @DisplayName("List devices by user: token truncated to 20 chars + '...'")
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
    @DisplayName("Unregister device by token")
    void unregisterDevice() throws Exception {
        register("u1", "tokenAAA", "web");

        mvc.perform(delete("/api/devices").param("token", "tokenAAA"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.status").value("unregistered"));

        assertEquals(0, repo.count());
    }

    // ------------------------------------------------------------------ 2. Send to a single token

    @Test
    @DisplayName("Send to a single token succeeds -> returns messageId")
    void sendToToken_success() throws Exception {
        when(messaging.send(any(Message.class))).thenReturn("projects/x/messages/123");

        postJson("/api/notifications/token", Map.of("token", "tokenAAA", "payload", payload("Hi", "Hello")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messageId").value("projects/x/messages/123"));

        verify(messaging).send(any(Message.class));
    }

    @Test
    @DisplayName("Send to token without title/body -> default text is used, FCM called")
    void sendToToken_blankTitleAndBody_useDefaults() throws Exception {
        when(messaging.send(any(Message.class))).thenReturn("msg-default");

        postJson("/api/notifications/token", Map.of("token", "tokenAAA", "payload", Map.of("title", "  ")))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messageId").value("msg-default"));

        verify(messaging).send(any(Message.class));
    }

    @Test
    @DisplayName("Title longer than 200 chars -> 400, FCM not called")
    void sendToToken_titleTooLong() throws Exception {
        postJson("/api/notifications/token", Map.of("token", "tokenAAA", "payload", payload("x".repeat(201), "body")))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"));

        verifyNoInteractions(messaging);
    }

    @Test
    @DisplayName("List all devices (admin dropdown): newest first, full token never returned")
    void listAllDevices() throws Exception {
        register("Thay Duc", "abcdefghijklmnopqrstuvwxyz0123456789", "web");
        register("Co Lan", "other-token", "android");

        mvc.perform(get("/api/devices"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.length()").value(2))
                .andExpect(jsonPath("$[?(@.userId=='Thay Duc')].tokenPreview").value("abcdefghijklmnopqrst..."))
                .andExpect(jsonPath("$[0].token").doesNotExist());
    }

    @Test
    @DisplayName("Send to a device by id -> messageId + owner; unknown id -> 404")
    void sendToDeviceById() throws Exception {
        register("Thay Duc", "tokenDuc", "web");
        Long id = repo.findByToken("tokenDuc").orElseThrow().getId();
        when(messaging.send(any(Message.class))).thenReturn("msg-device");

        postJson("/api/notifications/device/" + id, Map.of("title", "Thay Duc oi", "body", "Link slide"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.messageId").value("msg-device"))
                .andExpect(jsonPath("$.userId").value("Thay Duc"));

        postJson("/api/notifications/device/999999", Map.of("title", "x", "body", "y"))
                .andExpect(status().isNotFound());
    }

    @Test
    @DisplayName("FCM returns UNREGISTERED -> 502 FCM_ERROR and token removed from DB")
    void sendToToken_unregistered_removesToken() throws Exception {
        register("u1", "deadToken", "web");
        givenSendThrows(MessagingErrorCode.UNREGISTERED);

        postJson("/api/notifications/token", Map.of("token", "deadToken", "payload", payload("Hi", "Hello")))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.error").value("FCM_ERROR"))
                .andExpect(jsonPath("$.code").value("UNREGISTERED"));

        assertTrue(repo.findByToken("deadToken").isEmpty(), "dead token must be removed");
    }

    @Test
    @DisplayName("Other FCM error (INTERNAL) -> 502 but token is KEPT in DB")
    void sendToToken_otherError_keepsToken() throws Exception {
        register("u1", "goodToken", "web");
        givenSendThrows(MessagingErrorCode.INTERNAL);

        postJson("/api/notifications/token", Map.of("token", "goodToken", "payload", payload("Hi", "Hello")))
                .andExpect(status().isBadGateway())
                .andExpect(jsonPath("$.code").value("INTERNAL"));

        assertTrue(repo.findByToken("goodToken").isPresent());
    }

    // ------------------------------------------------------------------ 3. Send to user (multicast)

    @Test
    @DisplayName("Send to user with 3 devices, 1 dead token -> success=2, failure=1, dead token removed")
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
        assertEquals(3, repo.count());   // t1, t3 and t-other remain
    }

    @Test
    @DisplayName("Non-UNREGISTERED error (QUOTA_EXCEEDED): counted as failure but token NOT removed")
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
    @DisplayName("User without devices -> 0/0 and FCM not called")
    void sendToUser_noDevices() throws Exception {
        postJson("/api/notifications/user/ghost", payload("Hi", "Hello"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(0))
                .andExpect(jsonPath("$.failureCount").value(0));

        verifyNoInteractions(messaging);
    }

    // ------------------------------------------------------------------ 4. Broadcast

    @Test
    @DisplayName("Broadcast to devices of several users, dead tokens removed")
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
    @DisplayName("1001 tokens -> split into 3 batches (500 + 500 + 1)")
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
    @DisplayName("Subscribe -> send to topic -> unsubscribe")
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
    @DisplayName("Topic with invalid characters -> 400, FCM not called")
    void subscribe_invalidTopicName() throws Exception {
        postJson("/api/topics/subscribe", Map.of("token", "tokenAAA", "topic", "bad topic!"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("VALIDATION_FAILED"))
                .andExpect(jsonPath("$.fields.topic").exists());

        verifyNoInteractions(messaging);
    }

    // ------------------------------------------------------------------ 6. Order demo

    @Test
    @DisplayName("Order status update -> push to all of the user's devices")
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
    @DisplayName("Invalid order status / missing userId -> 400")
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
    @DisplayName("FULL FLOW: register 2 devices -> SHIPPING (1 dead token removed) -> DELIVERED with 1 token left")
    void fullFlow_registerThenOrderThenSelfCleaning() throws Exception {
        // 1. the user registers 2 devices
        register("alice", "phone-token", "android");
        register("alice", "laptop-token-dead", "web");
        mvc.perform(get("/api/devices/user/alice"))
                .andExpect(jsonPath("$.length()").value(2));

        // 2. order goes to SHIPPING: the laptop uninstalled the app -> UNREGISTERED
        givenMulticast(batch(ok(), fail(MessagingErrorCode.UNREGISTERED)));

        postJson("/api/orders/2002/status", Map.of("userId", "alice", "status", "SHIPPING"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(1))
                .andExpect(jsonPath("$.failureCount").value(1))
                .andExpect(jsonPath("$.removedInvalidTokens[0]").value("laptop-token-dead"));

        // 3. the dead token was removed automatically
        mvc.perform(get("/api/devices/user/alice"))
                .andExpect(jsonPath("$.length()").value(1))
                .andExpect(jsonPath("$[0].platform").value("android"));

        // 4. order DELIVERED: only 1 device is left
        givenMulticast(batch(ok()));

        postJson("/api/orders/2002/status", Map.of("userId", "alice", "status", "DELIVERED"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.successCount").value(1))
                .andExpect(jsonPath("$.failureCount").value(0))
                .andExpect(jsonPath("$.removedInvalidTokens.length()").value(0));

        // 5. user logs out -> unregister -> no device left to notify
        mvc.perform(delete("/api/devices").param("token", "phone-token")).andExpect(status().isOk());
        assertEquals(0, repo.count());
    }
}
