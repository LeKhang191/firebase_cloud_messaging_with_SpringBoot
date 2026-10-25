# Firebase Cloud Messaging

Demo tích hợp **Firebase Cloud Messaging (FCM)** vào ứng dụng **Spring Boot**, gồm 3 nội dung:

- **Device registration**: lấy token trên trình duyệt và lưu quan hệ giữa người dùng với thiết bị.
- **Push notifications**: gửi thông báo đến một token, các thiết bị của một người dùng hoặc một chủ đề (topic).
- **Business integration**: mô phỏng gửi thông báo khi trạng thái đơn hàng thay đổi.

Project có trang web demo, REST API, database H2 lưu token và 19 test method sử dụng Firebase giả lập.

## Yêu cầu

- **Windows x64** để dùng `start.bat`: script có thể tải JDK và Maven portable khi máy chưa có công cụ phù hợp.
- Trình duyệt **Chrome hoặc Edge** ở cửa sổ thường, cho phép thông báo.
- Tài khoản và project **Firebase** tại https://console.firebase.google.com.
- Kết nối Internet để tải thư viện và gửi/nhận thông báo.

Nếu chạy thủ công hoặc dùng macOS/Linux, chuẩn bị **JDK 17** và **Maven** trong PATH.

## Cài đặt và chạy

### 1. Tải project

Trên trang GitHub của project này, chọn **Code → Download ZIP**, rồi giải nén. Nếu dùng Git, chọn **Code → HTTPS**, sao chép URL của repository để clone.

Mở thư mục vừa tải. Thư mục gốc phải có `pom.xml`, `start.bat` và `src`. Thực hiện các lệnh trong tài liệu tại thư mục này.

### 2. Chuẩn bị Firebase project và khóa server

1. Đăng nhập https://console.firebase.google.com và tạo hoặc chọn project dùng cho demo.
2. Trong cài đặt project, tìm **Service accounts**.
3. Chọn tạo private key mới nếu tài khoản có quyền, rồi tải file JSON.
4. Đổi tên file thành `firebase-service-account.json` và đặt **cạnh `pom.xml`**.

> Service account chứa private key: không đưa lên GitHub, không đặt trong `static`, không gửi private key. Người thực hành nên dùng project và credential riêng.

### 3. Tạo cấu hình web và VAPID key

Trong cài đặt project, đăng ký hoặc chọn ứng dụng **Web**, rồi lấy cấu hình Firebase của ứng dụng đó.

Sao chép file mẫu thành file cấu hình local:

```powershell
# Windows PowerShell
Copy-Item src/main/resources/static/firebase-config.example.js src/main/resources/static/firebase-config.js
```

```bash
# macOS / Linux
cp src/main/resources/static/firebase-config.example.js src/main/resources/static/firebase-config.js
```

Mở `src/main/resources/static/firebase-config.js` và điền giá trị thật:

```javascript
self.FIREBASE_CONFIG = {
  apiKey: "API_KEY_CUA_BAN",
  authDomain: "AUTH_DOMAIN_TU_FIREBASE",
  projectId: "PROJECT_ID_CUA_BAN",
  storageBucket: "STORAGE_BUCKET_TU_FIREBASE",
  messagingSenderId: "MESSAGING_SENDER_ID_CUA_BAN",
  appId: "APP_ID_CUA_BAN"
};
self.VAPID_KEY = "PUBLIC_VAPID_KEY_CUA_BAN";
```

Để lấy VAPID key, tìm **Cloud Messaging → Web Push certificates** trong cài đặt project; tạo hoặc dùng cặp khóa hiện có và sao chép **public key**. Tên mục có thể thay đổi theo giao diện Console.

Dùng đúng các giá trị Firebase cung cấp, bao gồm `storageBucket`. Cấu hình web, VAPID key và service account phải thuộc cùng project. Không để giá trị mẫu trong file.

### 4. Chạy ứng dụng

**Windows — cách nhanh:** nhấp đúp `start.bat`, hoặc mở PowerShell tại thư mục gốc:

```powershell
.\start.bat
```

Script kiểm tra môi trường, file cấu hình và khởi động ứng dụng. Nếu thiếu service account hoặc cấu hình web còn placeholder `YOUR_...`, làm theo yêu cầu trên màn hình.

Lần đầu có thể mất vài phút do tải JDK/Maven hoặc dependencies. Chờ backend khởi động, rồi mở http://localhost:8080 nếu trình duyệt chưa tự mở.

> Nếu cổng 8080 đã bận, script có thể mở trang của tiến trình đang chạy rồi thoát. Sau khi sửa source, dừng backend cũ trước khi chạy lại để tránh xem nhầm phiên cũ.

### 5. Sử dụng

| Việc | Thao tác |
|---|---|
| Mở trang demo | http://localhost:8080 |
| Đăng ký thiết bị | Nhập `user1` → **Enable notifications & register** → chọn **Allow** |
| Gửi theo người dùng | Nhấn **Send to the userId above** |
| Tham gia chủ đề | Nhập `news` → **Subscribe** |
| Gửi theo chủ đề | Nhấn **Send to the topic above** |
| Mô phỏng đơn hàng | Nhấn **Simulate order shipping** |
| Rời chủ đề | Nhấn **Unsubscribe** |
| Hủy đăng ký thiết bị | Nhấn **Unregister** |

Nếu dùng giao diện minimal, nút đăng ký tên **Register browser**; chọn **User** hoặc **Topic**, nhập người nhận và nội dung rồi nhấn **Send notification**.

Để thử nhận khi trang ở nền: dùng hai trình duyệt hoặc hai profile, một bên đăng ký nhận, bên còn lại gửi. Chuyển trang nhận sang tab khác trước khi gửi.

Dừng backend: nhấn **Ctrl+C** trong cửa sổ đang chạy ứng dụng.

> H2 được cấu hình lưu file tại `./data/fcmdb`, nên dữ liệu không mặc nhiên mất khi khởi động lại. Phần đơn hàng chỉ tạo thông báo mô phỏng, chưa cập nhật một đơn hàng thật. Kết quả gửi thành công không đồng nghĩa người dùng đã đọc hoặc nhìn thấy thông báo.

## Chạy thủ công (tùy chọn)

Cần JDK 17+ và Maven đã hoạt động trong terminal:

```text
java -version
javac -version
mvn -v
mvn spring-boot:run
```

Truy cập http://localhost:8080. Vẫn cần chuẩn bị hai file cấu hình ở bước 2 và bước 3.

Source có `setup.bat` và `setup.sh` để chuẩn bị môi trường. `setup.sh` không tự cấu hình Firebase hoặc khởi động ứng dụng. Nếu dùng công cụ portable trên macOS/Linux, kiểm tra lại PATH/JAVA_HOME của terminal trước khi chạy Maven; thay đổi biến môi trường trong script không tự áp dụng cho shell cha.

## Chạy test

Tại thư mục chứa `pom.xml`:

```powershell
# Windows
.\test.bat
```

Hoặc dùng Maven trực tiếp khi môi trường đã sẵn sàng:

```bash
mvn test
```

Firebase được mock trong `FcmFlowTest`, nên test không gửi thông báo thật và không cần service account cho các lời gọi Firebase giả lập. Xem kết quả thực tế trong terminal; chỉ kết luận test đạt khi không có failure/error và build thành công.

## API chính

| Phương thức | Endpoint | Chức năng |
|---|---|---|
| POST | `/api/devices/register` | Đăng ký/cập nhật token |
| GET | `/api/devices/user/{userId}` | Xem thiết bị của user, token được rút gọn |
| DELETE | `/api/devices?token=...` | Xóa đăng ký trong backend |
| POST | `/api/notifications/token` | Gửi đến token |
| POST | `/api/notifications/user/{userId}` | Gửi đến các thiết bị của user |
| POST | `/api/notifications/topic/{topic}` | Gửi đến topic |
| POST | `/api/notifications/broadcast` | Gửi đến mọi token lưu trong ứng dụng |
| POST | `/api/topics/subscribe` | Đăng ký topic |
| POST | `/api/topics/unsubscribe` | Hủy đăng ký topic |
| POST | `/api/orders/{orderId}/status` | Mô phỏng thông báo trạng thái đơn |

Ví dụ gửi trạng thái đơn hàng bằng PowerShell:

```powershell
$body = @{
    userId = "user1"
    status = "SHIPPING"
} | ConvertTo-Json

Invoke-RestMethod `
    -Method Post `
    -Uri "http://localhost:8080/api/orders/1001/status" `
    -ContentType "application/json" `
    -Body $body
```

Trạng thái hỗ trợ: `CONFIRMED`, `SHIPPING`, `DELIVERED`, `CANCELLED`.

## Lỗi thường gặp

| Symptom | Cách xử lý |
|---|---|
| `JAVA_HOME is not defined correctly` | Trỏ JAVA_HOME đến thư mục JDK, không phải thư mục `bin`. Kiểm tra `mvn -v`; mở terminal mới nếu vừa đổi biến môi trường. |
| `Notification permission denied` | Cho phép Notifications trong quyền của localhost, tải lại trang rồi đăng ký lại. |
| Token chưa xuất hiện | Kiểm tra log trình duyệt, web config, public VAPID key, service worker và mạng. |
| Không đọc được service account | Kiểm tra file `firebase-service-account.json` nằm cạnh `pom.xml` và đọc được. |
| `SENDER_ID_MISMATCH` | Kiểm tra cấu hình frontend, token và credential backend thuộc cùng project. |
| HTTP 400 | Kiểm tra trường bắt buộc, JSON, enum trạng thái và tên topic. |
| HTTP 502 / `FCM_ERROR` | Xem code/message trả về để kiểm tra credential, project hoặc kết nối. |
| `successCount=0`, `failureCount=0` | Kiểm tra đã đăng ký token cho đúng user đích chưa. |
| Gửi được nhưng không thấy popup | Kiểm tra quyền thông báo của trình duyệt/hệ điều hành và trạng thái client; kết quả gửi không xác nhận hiển thị. |
| Vào localhost thấy ứng dụng khác | Kiểm tra ứng dụng đang chiếm cổng 8080; dừng đúng tiến trình xung đột trước khi chạy. |
| Sửa giao diện mà không thấy thay đổi | Thay đúng `src/main/resources/static/index.html`, dừng backend cũ, chạy lại và nhấn Ctrl+F5. Không dùng `preview.html` để chạy thật. |
| `test.bat` vẫn lỗi Java dù `start.bat` chạy được | Kiểm tra môi trường của terminal chạy test. JAVA_HOME được sửa trong tiến trình start.bat không tự sửa môi trường hệ thống. |

## Cấu trúc thư mục

| Đường dẫn | Nội dung |
|---|---|
| `pom.xml` | Dependencies và cấu hình build Maven |
| `start.bat` | Kiểm tra cấu hình, chuẩn bị công cụ nếu thiếu và chạy demo trên Windows |
| `setup.bat`, `setup.sh` | Chuẩn bị môi trường |
| `test.bat`, `test.sh` | Chạy kiểm thử |
| `firebase-service-account.json` | Khóa server local, không commit |
| `src/main/java/com/seminar/fcm/config/` | Khởi tạo Firebase Admin SDK |
| `src/main/java/com/seminar/fcm/controller/` | REST API |
| `src/main/java/com/seminar/fcm/service/` | Quản lý token và gửi thông báo |
| `src/main/java/com/seminar/fcm/entity/`, `repository/` | Entity và truy cập dữ liệu |
| `src/main/java/com/seminar/fcm/dto/`, `exception/` | Dữ liệu request/response và xử lý lỗi |
| `src/main/resources/application.yml` | Cổng, H2 và đường dẫn credential |
| `src/main/resources/static/index.html` | Giao diện demo |
| `src/main/resources/static/firebase-config.example.js` | Mẫu cấu hình web |
| `src/main/resources/static/firebase-config.js` | Cấu hình web local |
| `src/main/resources/static/firebase-messaging-sw.js` | Service worker nhận thông báo nền |
| `src/test/java/com/seminar/fcm/FcmFlowTest.java` | Kiểm thử với Firebase giả lập |

Đây là bản demo phục vụ seminar. Trước khi triển khai công khai cần bổ sung xác thực, phân quyền API gửi, quản lý credential và cấu hình database phù hợp.