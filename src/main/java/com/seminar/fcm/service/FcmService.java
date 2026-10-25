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
    private static final int MAX_BATCH = 500;

    private final FirebaseMessaging messaging;
    private final DeviceTokenService deviceTokenService;

    public FcmService(FirebaseMessaging messaging, DeviceTokenService deviceTokenService) {
        this.messaging = messaging;
        this.deviceTokenService = deviceTokenService;
    }

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
            if (e.getMessagingErrorCode() == MessagingErrorCode.UNREGISTERED) {
                deviceTokenService.removeTokens(List.of(token));
                log.warn("Token UNREGISTERED, removed from database");
            }
            throw e;
        }
    }

    public SendResult sendToUser(String userId, NotificationPayload payload) throws FirebaseMessagingException {
        return sendMulticast(deviceTokenService.findTokensByUserId(userId), payload);
    }

    public SendResult sendToAll(NotificationPayload payload) throws FirebaseMessagingException {
        return sendMulticast(deviceTokenService.findAllTokens(), payload);
    }

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
        log.info("Multicast done: success={}, failure={}, removed={}", success, failure, invalid.size());
        return new SendResult(success, failure, invalid, errors);
    }

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
        return AndroidConfig.builder().setPriority(AndroidConfig.Priority.HIGH).build();
    }
}
