package com.seminar.fcm.dto;

import jakarta.validation.constraints.Size;

import java.util.Map;

/**
 * Title and body are optional: when blank the server falls back to a default text
 * (see FcmService.DEFAULT_TITLE / DEFAULT_BODY). Limits keep the whole FCM payload under 4 KB.
 */
public record NotificationPayload(
        @Size(max = 200) String title,
        @Size(max = 1000) String body,
        String imageUrl,
        Map<String, String> data) {
}
