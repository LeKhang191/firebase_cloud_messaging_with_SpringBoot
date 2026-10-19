package com.seminar.fcm.dto;

import jakarta.validation.constraints.NotBlank;

public record RegisterDeviceRequest(
        @NotBlank String userId,
        @NotBlank String token,
        String platform) {
}
