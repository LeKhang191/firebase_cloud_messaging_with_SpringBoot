package com.seminar.fcm.controller;

import com.seminar.fcm.dto.RegisterDeviceRequest;
import com.seminar.fcm.entity.DeviceToken;
import com.seminar.fcm.service.DeviceTokenService;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.*;

import java.util.List;
import java.util.Map;

@RestController
@RequestMapping("/api/devices")
public class DeviceController {
    private final DeviceTokenService service;

    public DeviceController(DeviceTokenService service) {
        this.service = service;
    }

    @PostMapping("/register")
    public Map<String, Object> register(@Valid @RequestBody RegisterDeviceRequest req) {
        DeviceToken saved = service.register(req);
        return Map.of("id", saved.getId(), "userId", saved.getUserId(), "platform", saved.getPlatform());
    }

    @DeleteMapping
    public Map<String, String> unregister(@RequestParam String token) {
        service.unregister(token);
        return Map.of("status", "unregistered");
    }

    @GetMapping("/user/{userId}")
    public List<Map<String, Object>> listByUser(@PathVariable String userId) {
        return service.findByUserId(userId).stream()
                .map(d -> Map.<String, Object>of(
                        "id", d.getId(),
                        "platform", d.getPlatform(),
                        "tokenPreview", d.getToken().substring(0, Math.min(20, d.getToken().length())) + "...",
                        "updatedAt", d.getUpdatedAt().toString()))
                .toList();
    }
}
