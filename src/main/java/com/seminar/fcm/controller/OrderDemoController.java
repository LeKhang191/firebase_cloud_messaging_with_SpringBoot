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
        // (ở đây lẽ ra: cập nhật DB đơn hàng trước)
        String body = switch (req.status()) {
            case CONFIRMED -> "Đơn hàng đã được xác nhận";
            case SHIPPING -> "Đơn hàng đang trên đường giao đến bạn";
            case DELIVERED -> "Đơn hàng đã giao thành công. Cảm ơn bạn!";
            case CANCELLED -> "Đơn hàng đã bị hủy";
        };

        NotificationPayload payload = new NotificationPayload(
                "Đơn hàng #" + orderId,
                body,
                null,
                Map.of("type", "ORDER_STATUS", "orderId", orderId, "status", req.status().name()));

        return fcmService.sendToUser(req.userId(), payload);
    }
}
