package com.seminar.fcm.dto;

import com.seminar.fcm.entity.DeviceToken;

/** Public view of a registered device: the full token is never returned. */
public record DeviceInfo(Long id, String userId, String platform, String tokenPreview, String updatedAt) {
    public static DeviceInfo from(DeviceToken d) {
        String token = d.getToken();
        return new DeviceInfo(
                d.getId(),
                d.getUserId(),
                d.getPlatform(),
                token.substring(0, Math.min(20, token.length())) + "...",
                d.getUpdatedAt() == null ? null : d.getUpdatedAt().toString());
    }
}
