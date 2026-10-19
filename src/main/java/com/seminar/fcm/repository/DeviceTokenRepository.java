package com.seminar.fcm.repository;

import com.seminar.fcm.entity.DeviceToken;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.Collection;
import java.util.List;
import java.util.Optional;

public interface DeviceTokenRepository extends JpaRepository<DeviceToken, Long> {

    List<DeviceToken> findByUserId(String userId);

    Optional<DeviceToken> findByToken(String token);

    void deleteByToken(String token);

    void deleteByTokenIn(Collection<String> tokens);
}
