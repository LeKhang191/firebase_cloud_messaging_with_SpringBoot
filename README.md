# FCM + Spring Boot Demo

Firebase Cloud Messaging (FCM) integrated into a Spring Boot microservice:
**push notifications**, **notification topics** and **device registration**, with a small web client for the demo.

**Stack:** Java 17+, Spring Boot 3.3.5, Spring Data JPA (H2), Firebase Admin SDK 9.3.0, Firebase JS SDK 10.

## Quick start (Windows, one click)

1. Double-click **`start.bat`**.
2. First run only: it installs missing tools, asks for your Firebase service account key and web config.
3. The browser opens at http://localhost:8080 when the app is ready.

Full step-by-step guide (manual and one-click): see **`howtorun.txt`**.
Code walkthrough: see **`CODE-EXPLANATION.txt`**.

## Required local files (not in the repo)

| File | Purpose |
|---|---|
| `firebase-service-account.json` (project root) | Server key used by the Firebase Admin SDK |
| `src/main/resources/static/firebase-config.js` | Web config + VAPID key (copy from `firebase-config.example.js`) |

Both must belong to the same Firebase project. Never commit them.

## Scripts

| Script | Purpose |
|---|---|
| `start.bat` | Install missing tools, check Firebase config, run the app (Windows) |
| `setup.bat` / `setup.sh` | Install JDK 17 + Maven only |
| `test.bat` / `test.sh` | Run the autotests (Firebase is mocked, no key needed) |

## API

| Method | Endpoint | Description |
|---|---|---|
| POST | `/api/devices/register` | Register or update a device token |
| DELETE | `/api/devices?token=...` | Unregister a device |
| GET | `/api/devices/user/{userId}` | List a user's devices |
| POST | `/api/notifications/token` | Send to one token |
| POST | `/api/notifications/user/{userId}` | Send to all devices of a user |
| POST | `/api/notifications/broadcast` | Send to all devices |
| POST | `/api/notifications/topic/{topic}` | Send to a topic |
| POST | `/api/topics/subscribe` / `/unsubscribe` | Manage topic subscription |
| POST | `/api/orders/{orderId}/status` | Demo: order status change -> push |

Example:

```bash
curl -X POST localhost:8080/api/notifications/user/user1 \
  -H "Content-Type: application/json" \
  -d '{"title":"Hi","body":"Hello user1"}'
```

## Project structure

```
src/main/java/com/seminar/fcm
  config/       FirebaseConfig          Firebase Admin SDK setup
  entity/       DeviceToken             stored device tokens
  repository/   DeviceTokenRepository
  dto/          request / response objects
  service/      DeviceTokenService      register / unregister / cleanup
                FcmService              all FCM calls
  controller/   Device, Notification, OrderDemo
  exception/    GlobalExceptionHandler
src/main/resources/static               web client + service worker
src/test/java/...                       FcmFlowTest (19 tests)
```
