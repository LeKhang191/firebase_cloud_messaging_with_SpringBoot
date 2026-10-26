package com.seminar.fcm;

import com.google.firebase.FirebaseApp;
import com.google.firebase.messaging.FirebaseMessaging;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Admin-only endpoints are locked when app.admin-key is set; device registration stays open. */
@SpringBootTest(properties = {
        "spring.datasource.url=jdbc:h2:mem:fcmadmintest;DB_CLOSE_DELAY=-1",
        "spring.jpa.hibernate.ddl-auto=create-drop",
        "firebase.credentials-path=classpath:/not-used.json",
        "app.admin-key=s3cret"
})
@AutoConfigureMockMvc
class AdminKeyTest {

    @Autowired MockMvc mvc;
    @MockBean FirebaseApp firebaseApp;
    @MockBean FirebaseMessaging messaging;

    @Test
    @DisplayName("Config tells the UI that an admin key is required")
    void configReportsKeyRequired() throws Exception {
        mvc.perform(get("/api/config"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.adminKeyRequired").value(true));
    }

    @Test
    @DisplayName("Admin endpoints: 401 without key, 200 with the right key, 401 with a wrong key")
    void adminEndpointsNeedKey() throws Exception {
        mvc.perform(get("/api/devices")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/devices").header("X-Admin-Key", "wrong")).andExpect(status().isUnauthorized());
        mvc.perform(get("/api/devices").header("X-Admin-Key", "s3cret")).andExpect(status().isOk());

        mvc.perform(post("/api/notifications/broadcast")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"title\":\"a\",\"body\":\"b\"}"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.error").value("ADMIN_KEY_REQUIRED"));
    }

    @Test
    @DisplayName("Device registration stays open without a key")
    void registerStaysOpen() throws Exception {
        mvc.perform(post("/api/devices/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"userId\":\"u1\",\"token\":\"tokenAAA\"}"))
                .andExpect(status().isOk());
    }
}
