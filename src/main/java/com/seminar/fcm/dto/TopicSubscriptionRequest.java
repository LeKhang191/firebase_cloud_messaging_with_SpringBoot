package com.seminar.fcm.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record TopicSubscriptionRequest(
        @NotBlank String token,
        @NotBlank @Pattern(regexp = "[a-zA-Z0-9-_.~%]+", message = "Topic may only contain letters, digits and - _ . ~ %") String topic) {
}
