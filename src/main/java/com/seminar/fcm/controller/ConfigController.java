package com.seminar.fcm.controller;

import com.seminar.fcm.security.AdminKeyInterceptor;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.util.Map;

/** Lets the UI know whether it must ask for the admin key. */
@RestController
@RequestMapping("/api/config")
public class ConfigController {
    private final AdminKeyInterceptor adminKey;

    public ConfigController(AdminKeyInterceptor adminKey) {
        this.adminKey = adminKey;
    }

    @GetMapping
    public Map<String, Object> config() {
        return Map.of("adminKeyRequired", adminKey.isEnabled());
    }
}
