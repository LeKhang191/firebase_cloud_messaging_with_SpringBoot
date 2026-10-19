package com.seminar.fcm.dto;

import jakarta.validation.constraints.NotBlank;
import jakarta.validation.constraints.Pattern;

public record TopicSubscriptionRequest(
        @NotBlank String token,
        @NotBlank @Pattern(regexp = "[a-zA-Z0-9-_.~%]+", message = "Topic chỉ gồm chữ, số, - _ . ~ %") String topic) {
}
