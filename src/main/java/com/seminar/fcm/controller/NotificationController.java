package com.seminar.fcm.controller;

import com.google.firebase.messaging.FirebaseMessagingException;
import com.google.firebase.messaging.TopicManagementResponse;
import com.seminar.fcm.dto.*;
import com.seminar.fcm.entity.DeviceToken;
import com.seminar.fcm.service.DeviceTokenService;
import com.seminar.fcm.service.FcmService;
import jakarta.validation.Valid;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.server.ResponseStatusException;

import java.util.Map;

@RestController
@RequestMapping("/api")
public class NotificationController {
    private final FcmService fcmService;
    private final DeviceTokenService deviceTokenService;

    public NotificationController(FcmService fcmService, DeviceTokenService deviceTokenService) {
        this.fcmService = fcmService;
        this.deviceTokenService = deviceTokenService;
    }

    @PostMapping("/notifications/token")
    public Map<String, String> sendToToken(@Valid @RequestBody SendToTokenRequest req) throws FirebaseMessagingException {
        return Map.of("messageId", fcmService.sendToToken(req.token(), req.payload()));
    }

    /** Admin unicast: pick a device from the list (by id) instead of handling raw tokens in the browser. */
    @PostMapping("/notifications/device/{id}")
    public Map<String, String> sendToDevice(@PathVariable Long id,
                                            @Valid @RequestBody NotificationPayload payload) throws FirebaseMessagingException {
        DeviceToken device = deviceTokenService.findById(id)
                .orElseThrow(() -> new ResponseStatusException(HttpStatus.NOT_FOUND, "Device not found: " + id));
        return Map.of("messageId", fcmService.sendToToken(device.getToken(), payload),
                "userId", device.getUserId());
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
