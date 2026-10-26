package com.seminar.fcm.security;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.servlet.HandlerInterceptor;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;

/**
 * Optional protection for admin-only endpoints. Disabled while app.admin-key (env ADMIN_KEY) is empty.
 * Needed when the demo is exposed to the Internet through a tunnel: otherwise anyone holding the link
 * could broadcast to every device.
 * Open on purpose: device register/unregister, self-test (/notifications/token), topic subscribe/unsubscribe.
 */
@Component
public class AdminKeyInterceptor implements HandlerInterceptor {
    public static final String HEADER = "X-Admin-Key";

    private final String adminKey;

    public AdminKeyInterceptor(@Value("${app.admin-key:}") String adminKey) {
        this.adminKey = adminKey == null ? "" : adminKey.trim();
    }

    public boolean isEnabled() {
        return !adminKey.isEmpty();
    }

    @Override
    public boolean preHandle(HttpServletRequest request, HttpServletResponse response, Object handler) throws Exception {
        if (!isEnabled() || !isAdminOnly(request.getMethod(), request.getRequestURI())) {
            return true;
        }
        String provided = request.getHeader(HEADER);
        if (provided != null && MessageDigest.isEqual(
                provided.getBytes(StandardCharsets.UTF_8), adminKey.getBytes(StandardCharsets.UTF_8))) {
            return true;
        }
        response.setStatus(HttpServletResponse.SC_UNAUTHORIZED);
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding("UTF-8");
        response.getWriter().write("{\"error\":\"ADMIN_KEY_REQUIRED\",\"message\":\"Missing or wrong " + HEADER + "\"}");
        return false;
    }

    static boolean isAdminOnly(String method, String path) {
        if ("GET".equals(method)) {
            return path.equals("/api/devices") || path.startsWith("/api/devices/user/");
        }
        if ("POST".equals(method)) {
            return path.startsWith("/api/notifications/user/")
                    || path.startsWith("/api/notifications/device/")
                    || path.startsWith("/api/notifications/topic/")
                    || path.equals("/api/notifications/broadcast")
                    || path.startsWith("/api/orders/");
        }
        return false;
    }
}
