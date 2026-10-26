package com.seminar.fcm.controller;

import com.seminar.fcm.dto.DeviceInfo;
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

    @GetMapping
    public List<DeviceInfo> listAll() {
        return service.findAll().stream().map(DeviceInfo::from).toList();
    }

    @GetMapping("/user/{userId}")
    public List<DeviceInfo> listByUser(@PathVariable String userId) {
        return service.findByUserId(userId).stream().map(DeviceInfo::from).toList();
    }
}
