package com.seminar.fcm.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record OrderStatusRequest(
        @NotBlank String userId,
        @NotNull OrderStatus status) {

    public enum OrderStatus { CONFIRMED, SHIPPING, DELIVERED, CANCELLED }
}
