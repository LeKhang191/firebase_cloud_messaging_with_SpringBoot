package com.seminar.fcm.service;

import com.google.firebase.messaging.*;
import com.seminar.fcm.dto.NotificationPayload;
import com.seminar.fcm.dto.SendResult;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.ArrayList;
import java.util.List;
import java.util.Map;

@Service
public class FcmService {

    private static final Logger log = LoggerFactory.getLogger(FcmService.class);
    private static final int MAX_BATCH = 500;   // FCM giới hạn 500 token / 1 lần multicast

    private final FirebaseMessaging messaging;
    private final DeviceTokenService deviceTokenService;

    public FcmService(FirebaseMessaging messaging, DeviceTokenService deviceTokenService) {
        this.messaging = messaging;
        this.deviceTokenService = deviceTokenService;
    }

    // ------------------------------------------------------------------
    // 1) Gửi tới 1 thiết bị (token)
    // ------------------------------------------------------------------
    public String sendToToken(String token, NotificationPayload payload) throws FirebaseMessagingException {
        Message message = Message.builder()
                .setToken(token)
                .setNotification(toNotification(payload))
                .putAllData(dataOf(payload))
                .setAndroidConfig(androidConfig())
                .build();
        try {
            String messageId = messaging.send(message);
            log.info("Sent to token, messageId={}", messageId);
            return messageId;
        } catch (FirebaseMessagingException e) {
            // UNREGISTERED = app bị gỡ / token hết hạn => xóa khỏi DB
            if (e.getMessagingErrorCode() == MessagingErrorCode.UNREGISTERED) {
                deviceTokenService.removeTokens(List.of(token));
                log.warn("Token UNREGISTERED, đã xóa khỏi DB");
            }
            throw e;
        }
    }

    // ------------------------------------------------------------------
    // 2) Gửi tới mọi thiết bị của 1 user (multicast)
    // ------------------------------------------------------------------
    public SendResult sendToUser(String userId, NotificationPayload payload) throws FirebaseMessagingException {
        return sendMulticast(deviceTokenService.findTokensByUserId(userId), payload);
    }

    // ------------------------------------------------------------------
    // 3) Gửi tới tất cả thiết bị đã đăng ký (broadcast)
    // ------------------------------------------------------------------
    public SendResult sendToAll(NotificationPayload payload) throws FirebaseMessagingException {
        return sendMulticast(deviceTokenService.findAllTokens(), payload);
    }

    /** Gửi theo lô 500 token, đồng thời dọn token chết dựa trên kết quả từng token. */
    private SendResult sendMulticast(List<String> tokens, NotificationPayload payload) throws FirebaseMessagingException {
        int success = 0;
        int failure = 0;
        List<String> invalid = new ArrayList<>();
        List<String> errors = new ArrayList<>();

        for (int from = 0; from < tokens.size(); from += MAX_BATCH) {
            List<String> batch = tokens.subList(from, Math.min(from + MAX_BATCH, tokens.size()));

            MulticastMessage message = MulticastMessage.builder()
                    .addAllTokens(batch)
                    .setNotification(toNotification(payload))
                    .putAllData(dataOf(payload))
                    .setAndroidConfig(androidConfig())
                    .build();

            BatchResponse response = messaging.sendEachForMulticast(message);
            success += response.getSuccessCount();
            failure += response.getFailureCount();

            // responses.get(i) tương ứng đúng batch.get(i)
            List<SendResponse> responses = response.getResponses();
            for (int i = 0; i < responses.size(); i++) {
                SendResponse r = responses.get(i);
                if (!r.isSuccessful()) {
                    FirebaseMessagingException ex = r.getException();
                    if (ex.getMessagingErrorCode() == MessagingErrorCode.UNREGISTERED) {
                        invalid.add(batch.get(i));
                    }
                    errors.add(ex.getMessagingErrorCode() + ": " + ex.getMessage());
                }
            }
        }

        deviceTokenService.removeTokens(invalid);
        log.info("Multicast xong: success={}, failure={}, removed={}", success, failure, invalid.size());
        return new SendResult(success, failure, invalid, errors);
    }

    // ------------------------------------------------------------------
    // 4) Topic: gửi tới mọi thiết bị đã subscribe topic
    // ------------------------------------------------------------------
    public String sendToTopic(String topic, NotificationPayload payload) throws FirebaseMessagingException {
        Message message = Message.builder()
                .setTopic(topic)
                .setNotification(toNotification(payload))
                .putAllData(dataOf(payload))
                .setAndroidConfig(androidConfig())
                .build();
        return messaging.send(message);
    }

    public TopicManagementResponse subscribeToTopic(String token, String topic) throws FirebaseMessagingException {
        return messaging.subscribeToTopic(List.of(token), topic);
    }

    public TopicManagementResponse unsubscribeFromTopic(String token, String topic) throws FirebaseMessagingException {
        return messaging.unsubscribeFromTopic(List.of(token), topic);
    }

    // ------------------------------------------------------------------
    // Helpers
    // ------------------------------------------------------------------
    private Notification toNotification(NotificationPayload p) {
        Notification.Builder builder = Notification.builder()
                .setTitle(p.title())
                .setBody(p.body());
        if (p.imageUrl() != null && !p.imageUrl().isBlank()) {
            builder.setImage(p.imageUrl());
        }
        return builder.build();
    }

    private Map<String, String> dataOf(NotificationPayload p) {
        return p.data() == null ? Map.of() : p.data();
    }

    private AndroidConfig androidConfig() {
        // HIGH: đánh thức thiết bị Android ngay cả khi đang Doze
        return AndroidConfig.builder().setPriority(AndroidConfig.Priority.HIGH).build();
    }
}
