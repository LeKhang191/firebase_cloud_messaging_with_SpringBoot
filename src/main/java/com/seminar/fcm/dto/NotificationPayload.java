package com.seminar.fcm.dto;

import jakarta.validation.constraints.NotBlank;

import java.util.Map;

public record NotificationPayload(
        @NotBlank String title,
        @NotBlank String body,
        String imageUrl,
        Map<String, String> data) {
}
