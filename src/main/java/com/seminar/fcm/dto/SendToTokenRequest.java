package com.seminar.fcm.dto;

import jakarta.validation.Valid;
import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.NotNull;

public record SendToTokenRequest(
        @NotBlank String token,
        @NotNull @Valid NotificationPayload payload) {
}
