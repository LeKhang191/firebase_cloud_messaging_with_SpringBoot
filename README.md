# Firebase Cloud Messaging

Demo tích hợp **Firebase Cloud Messaging (FCM)** vào ứng dụng **Spring Boot**, gồm 3 nội dung:

- **Device registration**: lấy token trên trình duyệt và lưu quan hệ giữa người dùng với thiết bị.
- **Push notifications**: gửi thông báo đến một token, các thiết bị của một người dùng hoặc một chủ đề (topic).
- **Business integration**: mô phỏng gửi thông báo khi trạng thái đơn hàng thay đổi.

Project có trang web demo, REST API, database H2 lưu token và 19 test method sử dụng Firebase giả lập.

## Yêu cầu

- **Windows x64, macOS hoặc Linux**. Chọn `start.bat` trên Windows và `start.sh` trên macOS/Linux.
- **Java JDK 17–21** và Maven tương thích. Các script setup sẽ kiểm tra công cụ có sẵn và chỉ chuẩn bị công cụ portable khi cần.
- Trình duyệt **Chrome hoặc Edge** ở cửa sổ thường, cho phép thông báo.
- Tài khoản và project **Firebase** tại https://console.firebase.google.com.
- Kết nối Internet để tải công cụ, thư viện và gửi/nhận thông báo.

Nếu chạy thủ công hoặc dùng macOS/Linux, chuẩn bị **JDK 17** và **Maven** trong PATH.

## Cài đặt và chạy

### 1. Tải project

Trên trang GitHub của project này, chọn **Code → Download ZIP**, rồi giải nén. Nếu dùng Git, chọn **Code → HTTPS**, sao chép URL của repository để clone.

Mở thư mục vừa tải. Thư mục gốc phải có pom.xml, start.bat, start.sh, setup.bat, setup.sh, test.bat, test.sh và thư mục src. Thực hiện các lệnh trong tài liệu tại thư mục này.

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

**macOS / Linux:**

Mở Terminal tại thư mục gốc của project và chạy:

```bash
chmod +x start.sh setup.sh test.sh
./start.sh
```

Script sẽ kiểm tra môi trường và cấu hình cần thiết trước khi khởi động ứng dụng. Nếu máy chưa có JDK hoặc Maven tương thích, script setup có thể tải công cụ portable vào thư mục `.tools/`.

Trước khi chạy, hãy hoàn tất các bước cấu hình Firebase ở mục 2 và mục 3. Nếu script báo thiếu file cấu hình hoặc yêu cầu bổ sung thông tin, hãy làm theo hướng dẫn trên Terminal.

Chờ Spring Boot khởi động. Nếu trình duyệt không tự mở, truy cập:

http://localhost:8080

Để chạy kiểm thử trước khi khởi động ứng dụng, dùng:

```bash
./test.sh
```

Để dừng ứng dụng, nhấn `Ctrl+C` trong Terminal đang chạy backend.


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

## Chạy kiểm thử

Mở Terminal hoặc PowerShell tại thư mục gốc của project (thư mục chứa file `pom.xml`).

**Cách 1: Chạy test bằng script có sẵn**

Trên Windows, chạy:

```powershell
.\test.bat
```

Trên macOS/Linux, chạy:

```bash
./test.sh
```

Nếu macOS/Linux báo không có quyền thực thi script, chạy lệnh sau trước:

```bash
chmod +x test.sh
```

**Cách 2: Chạy test trực tiếp bằng Maven**

Nếu máy đã có JDK tương thích và Maven, chạy:

```bash
mvn test
```

**Kết quả kiểm thử**

Các bài kiểm thử trong `FcmFlowTest` sử dụng Firebase giả lập (mock), nên không gửi thông báo Firebase thật và không cần file service account cho những lời gọi Firebase được giả lập.

Theo dõi kết quả trong Terminal. Chỉ xác nhận kiểm thử thành công khi Maven kết thúc với trạng thái `BUILD SUCCESS` và không có bài kiểm thử nào thất bại hoặc phát sinh lỗi.

## Giao diện React (thư mục `frontend/`)

Giao diện demo có hai tab: **Giảng viên** (tự kết nối và gửi thử) và **Admin** (gửi riêng một máy hoặc gửi tới tất cả). Title và Body đều sửa được trực tiếp; để trống thì máy chủ dùng nội dung mặc định.

| Chế độ | Việc cần làm | API được gọi |
|---|---|---|
| Giảng viên tự test | Nhập tên thiết bị → **Cho phép thông báo** → sửa tiêu đề/nội dung → **Gửi thử** | `/api/devices/register`, `/api/topics/subscribe`, `/api/notifications/token` |
| Admin gửi riêng | Chọn thiết bị trong dropdown → nhập nội dung (tùy chọn) → **Gửi riêng** | `GET /api/devices`, `/api/notifications/device/{id}` |
| Admin gửi tất cả | Giữ topic `all_devices` → nhập nội dung (tùy chọn) → **Gửi tới tất cả** | `/api/notifications/topic/{topic}` |

Mỗi máy khi kết nối sẽ tự tham gia topic `all_devices`, nên gửi tới topic này là mọi máy cùng nhận. Mở `http://localhost:8080/#admin` để vào thẳng tab Admin.

**Dựng lại giao diện sau khi sửa code trong `frontend/`** (cần Node.js 18+): chạy `build-frontend.bat` (Windows) hoặc `./build-frontend.sh` (macOS/Linux). Script build rồi chép kết quả vào `src/main/resources/static/`. Bản build sẵn đã nằm trong `static/`, nên chỉ chạy `start.bat` là có giao diện.

**Chạy chế độ phát triển:** `mvn spring-boot:run` ở thư mục gốc, rồi `cd frontend && npm install && npm run dev`, mở http://localhost:5173 (Vite tự chuyển tiếp `/api` và `/firebase-config.js` sang cổng 8080).

### Chia sẻ qua Cloudflare Tunnel

```text
cloudflared tunnel --url http://localhost:8080
```

Lệnh in ra một link `https://….trycloudflare.com`. Link này **đổi mỗi lần chạy lại lệnh**, nên gửi link mới cho người xem mỗi lần demo. Khi mở link ra Internet, nên đặt mã admin để người ngoài không gửi thông báo bừa được:

```powershell
$env:ADMIN_KEY = "mat-khau-cua-ban"; .\start.bat
```

Khi `ADMIN_KEY` được đặt, tab Admin yêu cầu nhập mã. Việc đăng ký thiết bị và gửi thử cho chính máy mình vẫn mở. Nếu không đặt, mọi API đều mở như trước (chỉ nên dùng trên localhost).

**iPhone/iPad:** Safari chỉ nhận thông báo web khi trang đã được thêm vào Màn hình chính (Chia sẻ → Thêm vào MH chính) và mở từ biểu tượng đó, yêu cầu iOS 16.4 trở lên. Giao diện sẽ hiện hướng dẫn này khi phát hiện thiết bị iOS.

## API chính

| Phương thức | Endpoint | Chức năng |
|---|---|---|
| POST | `/api/devices/register` | Đăng ký/cập nhật token |
| GET | `/api/devices` | Danh sách mọi thiết bị đã đăng ký (token rút gọn) |
| GET | `/api/devices/user/{userId}` | Xem thiết bị của user, token được rút gọn |
| DELETE | `/api/devices?token=...` | Xóa đăng ký trong backend |
| POST | `/api/notifications/token` | Gửi đến token |
| POST | `/api/notifications/device/{id}` | Gửi riêng đến một thiết bị theo id (dropdown của Admin) |
| POST | `/api/notifications/user/{userId}` | Gửi đến các thiết bị của user |
| POST | `/api/notifications/topic/{topic}` | Gửi đến topic |
| POST | `/api/notifications/broadcast` | Gửi đến mọi token lưu trong ứng dụng |
| POST | `/api/topics/subscribe` | Đăng ký topic |
| POST | `/api/topics/unsubscribe` | Hủy đăng ký topic |
| POST | `/api/orders/{orderId}/status` | Mô phỏng thông báo trạng thái đơn |
| GET | `/api/config` | Cho giao diện biết có cần mã admin hay không |

`title` và `body` của mọi API gửi là tùy chọn: để trống thì dùng “Thông báo” / “Bạn có một thông báo mới”. Giới hạn: title tối đa 200 ký tự, body tối đa 1000 ký tự. Khi đặt `ADMIN_KEY`, các API admin (danh sách thiết bị, gửi theo user/thiết bị/topic/broadcast, đơn hàng) cần header `X-Admin-Key`.

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
| Sửa giao diện mà không thấy thay đổi | Sửa trong `frontend/src/`, chạy `build-frontend.bat` (hoặc `.sh`), rồi nhấn Ctrl+F5. |
| Tab Admin báo “Thiếu hoặc sai mã admin” | Máy chủ đang bật `ADMIN_KEY`; nhập đúng mã hoặc bỏ biến môi trường này. |
| Admin không thấy máy của người xem | Người xem phải bấm **Cho phép thông báo** trước; danh sách tự cập nhật mỗi 5 giây. |
| `test.bat` vẫn lỗi Java dù `start.bat` chạy được | Kiểm tra môi trường của terminal chạy test. JAVA_HOME được sửa trong tiến trình start.bat không tự sửa môi trường hệ thống. |

## Cấu trúc thư mục

| Đường dẫn | Nội dung |
|---|---|
| `pom.xml` | Dependencies và cấu hình build Maven |
| `start.bat` | Kiểm tra cấu hình, chuẩn bị công cụ nếu thiếu và chạy demo trên Windows |
| `start.sh` | Kiểm tra cấu hình, chuẩn bị công cụ nếu thiếu và chạy demo trên macOS/Linux |
| `setup.bat`, `setup.sh` | Chuẩn bị môi trường |
| `test.bat`, `test.sh` | Chạy kiểm thử |
| `firebase-service-account.json` | Khóa server local, không commit |
| `src/main/java/com/seminar/fcm/config/` | Khởi tạo Firebase Admin SDK |
| `src/main/java/com/seminar/fcm/controller/` | REST API |
| `src/main/java/com/seminar/fcm/service/` | Quản lý token và gửi thông báo |
| `src/main/java/com/seminar/fcm/entity/`, `repository/` | Entity và truy cập dữ liệu |
| `src/main/java/com/seminar/fcm/dto/`, `exception/` | Dữ liệu request/response và xử lý lỗi |
| `src/main/resources/application.yml` | Cổng, H2 và đường dẫn credential |
| `frontend/` | Mã nguồn giao diện React + Vite + Tailwind |
| `build-frontend.bat`, `build-frontend.sh` | Build giao diện và chép vào `static/` |
| `src/main/resources/static/index.html`, `assets/` | Giao diện đã build (sinh ra từ `frontend/`) |
| `src/main/resources/static/firebase-config.example.js` | Mẫu cấu hình web |
| `src/main/resources/static/firebase-config.js` | Cấu hình web local |
| `src/main/resources/static/firebase-messaging-sw.js` | Service worker nhận thông báo nền |
| `src/test/java/com/seminar/fcm/FcmFlowTest.java`, `AdminKeyTest.java` | Kiểm thử với Firebase giả lập |

Đây là bản demo phục vụ seminar. Trước khi triển khai công khai cần bổ sung xác thực, phân quyền API gửi, quản lý credential và cấu hình database phù hợp.