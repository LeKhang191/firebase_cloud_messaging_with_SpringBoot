package com.seminar.fcm.dto;

import java.util.List;

/** Kết quả gửi hàng loạt (multicast). */
public record SendResult(
        int successCount,
        int failureCount,
        List<String> removedInvalidTokens,
        List<String> errors) {
}
