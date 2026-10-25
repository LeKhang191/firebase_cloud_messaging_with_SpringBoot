# FCM + Spring Boot Microservice – Seminar Demo

Demo **Firebase Cloud Messaging (FCM)** intergrate SpringBoot have 3 functions:
**Push notifications**, **Notification topics**, **Device registration**.

**TechStack:** Java 17+, Spring Boot 3.3.5, Spring Data JPA (H2), Firebase Admin SDK 9.3.0, Web client (Firebase JS SDK 10).


---

## 1. INSTALLATION

| TOOLS | VERSON | CHECK |
|---|---|---|
| JDK | 17+ Above | `java -version` |
| Maven | 3.6.3 above | `mvn -version` |
| Browser | Chrome or Edge | |
| Google Account |  Firebase | |

- Use **IntelliJ IDEA** don't need to install Maven (already inside).

---

## 2. Config Firebase

### 2.1. Create project
1. go https://console.firebase.google.com → **Create a project**.
2. Name (EX: `fcm-seminar-demo`), turn off Google Analytics, click **Create project**.
3. Click project name to enter general page, click **⚙ → Project settings**.

### 2.2. Take `firebaseConfig` (Web app)
1. Tab **General** → scroll down **Your apps** → click **`</>` (Web)**.
2. Nickname (Ex: `fcm-web`) → **Register app**.
3. Copy values `apiKey`, `authDomain`, `projectId`, `storageBucket`, `messagingSenderId`, `appId`.
   (`measurementId` can skip.)

### 2.3. Take VAPID key
1. Tab **Cloud Messaging** → mục **Web configuration** → **Web Push certificates**.
2. Click **Generate key pair** → copying string (`VAPID_KEY`).

### 2.4. Install Service Account (key from server)
1. Tab **Service accounts** → **Generate new private key** → download JSON file.
2. Turn name into **`firebase-service-account.json`** and put **next to `pom.xml`**.

### 2.5. Config web client
Mở `src/main/resources/static/firebase-config.js` and write down values:

```js
self.FIREBASE_CONFIG = {
  apiKey: "...",
  authDomain: "<project-id>.firebaseapp.com",
  projectId: "<project-id>",
  storageBucket: "<project-id>.appspot.com",
  messagingSenderId: "...",
  appId: "..."
};
self.VAPID_KEY = "...";
```
(Ex file: `firebase-config.example.js`. File `firebase-config.js`.)

---

## 3. Running App

Make sure you have 2 things before run:
- `firebase-service-account.json` next to `pom.xml`
- `static/firebase-config.js` fullfilling

### Way A – Maven command line
```bash
cd fcm-demo            # folder contain pom.xml
mvn spring-boot:run
```


### Way B – IntelliJ IDEA
1. **File → Open** → select folder `fcm-demo` (folder have `pom.xml`) → **Trust Project**.
2. Waiting IntelliJ finished downloading Maven library successfully.
3. **File → Project Structure → Project** → choose **SDK = JDK 17+**.
4. Mở `src/main/java/com/seminar/fcm/FcmDemoApplication.java` → bấm **▶** next to `main` function → **Run**.

---

## 4. API (cURL)

```bash
# DEVICE REGISTRATION
curl -X POST localhost:8080/api/devices/register -H "Content-Type: application/json" \
  -d '{"userId":"user1","token":"<FCM_TOKEN>","platform":"web"}'

# SENT TO 1ST TOKEN
curl -X POST localhost:8080/api/notifications/token -H "Content-Type: application/json" \
  -d '{"token":"<FCM_TOKEN>","payload":{"title":"Hi","body":"Hello","data":{"k":"v"}}}'

# SEND ALL DEVICES TO ONE USER
curl -X POST localhost:8080/api/notifications/user/user1 -H "Content-Type: application/json" \
  -d '{"title":"Hi","body":"Hello user1"}'

# BROADCAST
curl -X POST localhost:8080/api/notifications/broadcast -H "Content-Type: application/json" \
  -d '{"title":"Bảo trì","body":"Hệ thống bảo trì lúc 22h"}'

# TOPIC: SUBCRIBE, SEND, ÚNUBCRIBE
curl -X POST localhost:8080/api/topics/subscribe -H "Content-Type: application/json" \
  -d '{"token":"<FCM_TOKEN>","topic":"news"}'
curl -X POST localhost:8080/api/notifications/topic/news -H "Content-Type: application/json" \
  -d '{"title":"Tin mới","body":"Có tin hot"}'
curl -X POST localhost:8080/api/topics/unsubscribe -H "Content-Type: application/json" \
  -d '{"token":"<FCM_TOKEN>","topic":"news"}'

# PACKAGE SIMULATION (CONFIRMED | SHIPPING | DELIVERED | CANCELLED)
curl -X POST localhost:8080/api/orders/1001/status -H "Content-Type: application/json" \
  -d '{"userId":"user1","status":"SHIPPING"}'

# USER DEVICES LIST / CANCEL REGISTRATION
curl localhost:8080/api/devices/user/user1
curl -X DELETE "localhost:8080/api/devices?token=<FCM_TOKEN>"
```
(Windows CMD: using Postman or escape comma `"` to `\"`.)

---

## 5. Project structure

```
firebase_cloud_messaging_with_SpringBoot
├── pom.xml
├── firebase-service-account.json
├── GIAI-THICH-CODE.txt
└── src/main
    ├── java/com/seminar/fcm
    │   ├── FcmDemoApplication.java
    │   ├── config/FirebaseConfig.java          init Firebase Admin SDK
    │   ├── entity/DeviceToken.java             token saving table
    │   ├── repository/DeviceTokenRepository.java
    │   ├── dto/                                request/response
    │   ├── service/DeviceTokenService.java     registration / cancel / clean token
    │   ├── service/FcmService.java             send token / user / broadcast / topic
    │   ├── controller/                         REST API
    │   └── exception/GlobalExceptionHandler.java
    └── resources
        ├── application.yml
        └── static/ (index.html, firebase-messaging-sw.js, firebase-config.js)
```

---