package com.seminar.fcm.controller;

import com.google.firebase.messaging.FirebaseMessagingException;
import com.seminar.fcm.dto.NotificationPayload;
import com.seminar.fcm.dto.OrderStatusRequest;
import com.seminar.fcm.dto.SendResult;
import com.seminar.fcm.service.FcmService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.Map;

@RestController
@RequestMapping("/api/orders")
public class OrderDemoController {
    private final FcmService fcmService;

    public OrderDemoController(FcmService fcmService) {
        this.fcmService = fcmService;
    }

    @PostMapping("/{orderId}/status")
    public SendResult updateStatus(@PathVariable String orderId,
                                   @Valid @RequestBody OrderStatusRequest req) throws FirebaseMessagingException {
        String body = switch (req.status()) {
            case CONFIRMED -> "Your order has been confirmed";
            case SHIPPING -> "Your order is on its way";
            case DELIVERED -> "Your order has been delivered. Thank you!";
            case CANCELLED -> "Your order has been cancelled";
        };

        NotificationPayload payload = new NotificationPayload(
                "Order #" + orderId,
                body,
                null,
                Map.of("type", "ORDER_STATUS", "orderId", orderId, "status", req.status().name()));

        return fcmService.sendToUser(req.userId(), payload);
    }
}
