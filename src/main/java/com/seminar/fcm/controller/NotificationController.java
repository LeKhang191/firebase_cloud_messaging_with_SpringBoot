package com.seminar.fcm.controller;

import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.TopicManagementResponse;
import com.seminar.fcm.dto.*;
import com.seminar.fcm.service.FcmService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class NotificationController {
    private final FcmService fcmService;

    public NotificationController(FcmService fcmService) {
        this.fcmService = fcmService;
    }

    @PostMapping("/notifications/token")
    public Map<String, String> sendToToken(@Valid @RequestBody SendToTokenRequest req) throws FirebaseMessagingException {
        return Map.of("messageId", fcmService.sendToToken(req.token(), req.payload()));
    }

    @PostMapping("/notifications/user/{userId}")
    public SendResult sendToUser(@PathVariable String userId,
                                 @Valid @RequestBody NotificationPayload payload) throws FirebaseMessagingException {
        return fcmService.sendToUser(userId, payload);
    }

    @PostMapping("/notifications/broadcast")
    public SendResult broadcast(@Valid @RequestBody NotificationPayload payload) throws FirebaseMessagingException {
        return fcmService.sendToAll(payload);
    }

    @PostMapping("/notifications/topic/{topic}")
    public Map<String, String> sendToTopic(@PathVariable String topic,
                                           @Valid @RequestBody NotificationPayload payload) throws FirebaseMessagingException {
        return Map.of("messageId", fcmService.sendToTopic(topic, payload));
    }

    @PostMapping("/topics/subscribe")
    public Map<String, Object> subscribe(@Valid @RequestBody TopicSubscriptionRequest req) throws FirebaseMessagingException {
        TopicManagementResponse r = fcmService.subscribeToTopic(req.token(), req.topic());
        return Map.of("successCount", r.getSuccessCount(), "failureCount", r.getFailureCount());
    }

    @PostMapping("/topics/unsubscribe")
    public Map<String, Object> unsubscribe(@Valid @RequestBody TopicSubscriptionRequest req) throws FirebaseMessagingException {
        TopicManagementResponse r = fcmService.unsubscribeFromTopic(req.token(), req.topic());
        return Map.of("successCount", r.getSuccessCount(), "failureCount", r.getFailureCount());
    }
}
