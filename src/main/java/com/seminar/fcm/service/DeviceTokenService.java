package com.seminar.fcm.service;

import com.seminar.fcm.dto.RegisterDeviceRequest;
import com.seminar.fcm.entity.DeviceToken;
import com.seminar.fcm.repository.DeviceTokenRepository;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.Collection;
import java.util.List;

@Service
public class DeviceTokenService {
    private final DeviceTokenRepository repository;

    public DeviceTokenService(DeviceTokenRepository repository) {
        this.repository = repository;
    }

    @Transactional
    public DeviceToken register(RegisterDeviceRequest req) {
        DeviceToken device = repository.findByToken(req.token()).orElseGet(DeviceToken::new);
        device.setToken(req.token());
        device.setUserId(req.userId());
        device.setPlatform(req.platform() == null ? "web" : req.platform());
        return repository.save(device);
    }

    @Transactional
    public void unregister(String token) {
        repository.deleteByToken(token);
    }

    @Transactional
    public void removeTokens(Collection<String> tokens) {
        if (!tokens.isEmpty()) {
            repository.deleteByTokenIn(tokens);
        }
    }

    @Transactional(readOnly = true)
    public List<DeviceToken> findByUserId(String userId) {
        return repository.findByUserId(userId);
    }

    @Transactional(readOnly = true)
    public List<String> findTokensByUserId(String userId) {
        return repository.findByUserId(userId).stream().map(DeviceToken::getToken).toList();
    }

    @Transactional(readOnly = true)
    public List<String> findAllTokens() {
        return repository.findAll().stream().map(DeviceToken::getToken).toList();
    }
}
