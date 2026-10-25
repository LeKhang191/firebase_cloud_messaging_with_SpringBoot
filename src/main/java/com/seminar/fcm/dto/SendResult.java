package com.seminar.fcm.dto;

import java.util.List;

public record SendResult(
        int successCount,
        int failureCount,
        List<String> removedInvalidTokens,
        List<String> errors) {
}
