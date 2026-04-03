# HƯỚNG DẪN SỬ DỤNG TÍNH NĂNG HIỆN TẠI CỦA UNISEND

Tài liệu này hướng dẫn cách sử dụng các tính năng đang có trong ứng dụng theo đúng trạng thái code hiện tại.

## 1. Tổng quan nhanh

Ứng dụng hiện có 4 tab chính:

1. Bản đồ
2. Đơn hàng
3. Trò chuyện
4. Hồ sơ

Các tính năng đang hoạt động thật:

1. Firebase Auth (đăng nhập, đăng ký bằng email và mật khẩu)
2. Firestore (lưu đơn, đọc danh sách đơn theo thời gian thực)
3. Supabase Storage (tải ảnh đơn hàng)
4. GPS và OpenStreetMap (lấy vị trí, chọn địa chỉ trên bản đồ)

Các tính năng đang ở mức giao diện mô phỏng:

1. Chat (chưa kết nối dữ liệu thật)
2. Hồ sơ (nhiều nút vẫn đang hiển thị thông báo UI-only)
3. Danh sách đơn gần trên tab Bản đồ (đang là dữ liệu mẫu)

## 2. Cách chạy ứng dụng

Chế độ Firebase thật (khuyến nghị):

1. flutter pub get
2. flutter run

Chế độ bỏ qua đăng nhập để test giao diện nhanh:

1. flutter run --dart-define=BYPASS_LOGIN=true

Lưu ý: Khi chạy Firebase thật, nếu cấu hình sai thì app sẽ hiện màn hình lỗi cấu hình Firebase thay vì tự chuyển sang chế độ local.

## 3. Luồng bắt đầu cho người dùng

1. Mở ứng dụng
2. Đăng nhập bằng email và mật khẩu, hoặc tạo tài khoản mới
3. Khi đăng ký mới, hệ thống tạo hồ sơ user trên Firestore với isVerified = false
4. Sau khi vào app, điều hướng bằng thanh tab bên dưới

## 4. Hướng dẫn tab Bản đồ

Tab Bản đồ đang dùng OpenStreetMap với các thao tác:

1. Nhấn nút GPS để xin quyền và lấy vị trí hiện tại
2. Nhấn nút cộng hoặc trừ để phóng to, thu nhỏ
3. Kéo panel dưới lên hoặc xuống để xem danh sách đơn khu vực (dữ liệu mẫu)
4. Nhấn Tạo đơn hàng mới để mở form tạo đơn

### Tạo đơn trên bản đồ

Trong form tạo đơn, thao tác theo thứ tự sau:

1. Nhập tiêu đề đơn
2. Nhập receiver_id
3. Chọn ảnh món đồ (camera hoặc thư viện)
4. Chọn địa chỉ lấy hàng trên bản đồ
5. Chọn địa chỉ giao hàng trên bản đồ
6. Nhấn Tạo đơn

Hệ thống sẽ xử lý:

1. Tải ảnh lên Supabase bucket orders
2. Tạo bản ghi đơn lên Firestore
3. Lưu đầy đủ senderLocation và receiverLocation (kinh độ, vĩ độ và địa chỉ nếu có)

Nếu thiếu ảnh hoặc thiếu một trong hai điểm địa chỉ, hệ thống sẽ chặn gửi và hiển thị thông báo.

## 5. Hướng dẫn tab Đơn hàng

Danh sách đơn lấy real-time từ Firestore và chia theo 4 trạng thái:

1. Chờ nhận đơn
2. Chờ giao hàng
3. Hoàn thành
4. Đã hủy

Mỗi thẻ đơn hiển thị:

1. Tiêu đề và mô tả
2. Điểm lấy hàng và điểm giao hàng
3. Khoảng cách dự kiến (km)
4. Hạn giao
5. Các nút thao tác theo quyền

### Quyền thao tác hiện tại

1. Nhận đơn:
   Người dùng không phải sender, receiver, carrier và đơn đang ở trạng thái waitingCarrier.
2. Hoàn tất giao:
   Chỉ carrier của đơn và đơn đang ở waitingDelivery.
3. Hủy đơn:
   Sender, receiver, carrier hoặc creator có thể hủy khi đơn ở waitingCarrier hoặc waitingDelivery.
4. Sửa địa chỉ:
   Chỉ sender hoặc creator, và chỉ khi đơn ở waitingCarrier, chưa có carrier.

Quyền sửa địa chỉ được ràng buộc cả ở giao diện và trong transaction Firestore để tránh sửa sai luồng.

### Đổi tài khoản để test nhanh

Trong tab Đơn hàng có nút đổi tài khoản thử nghiệm ở AppBar:

1. Nhập user id mới
2. Hoặc chọn nhanh từ danh sách user id gợi ý
3. Nhấn áp dụng để xem hành vi quyền theo vai trò khác nhau

## 6. Hướng dẫn tab Trò chuyện

Trang này hiện là giao diện mô phỏng:

1. Chưa có danh sách cuộc trò chuyện thật
2. Nút gửi tin, gửi ảnh, gửi âm thanh, gửi vị trí đang hiển thị thông báo UI-only
3. Chưa liên kết Firestore messages vào màn hình này

## 7. Hướng dẫn tab Hồ sơ

Trang này hiện có:

1. Chuyển đổi chế độ sáng hoặc tối (đang hoạt động)
2. Các thao tác còn lại như sửa hồ sơ, cập nhật avatar, xác thực, thanh toán, hỗ trợ, đăng xuất, xóa tài khoản hiện vẫn ở mức giao diện mô phỏng

## 8. Các lỗi thường gặp và cách xử lý

1. Lỗi cấu hình Firebase khi mở app:
   Kiểm tra google-services.json, plugin Google Services trên Android và cấu hình Firebase theo từng nền tảng.
2. Tải ảnh thất bại:
   Kiểm tra Supabase đã khởi tạo, bucket orders, quyền upload và kết nối mạng.
3. Không lấy được GPS:
   Kiểm tra đã bật Location Service, cấp quyền vị trí, và nếu dùng emulator thì đặt mock location.
4. Không thấy đơn trong danh sách:
   Kiểm tra đơn đã tạo thành công trên Firestore collection orders hay chưa.

## 9. Checklist test luồng hiện tại

1. Đăng ký tài khoản mới
2. Đăng nhập
3. Tạo đơn có ảnh và hai địa chỉ trên bản đồ
4. Vào tab Đơn hàng, xác nhận đơn xuất hiện trong Chờ nhận đơn
5. Đổi user id thử nghiệm, nhận đơn
6. Carrier bấm Hoàn tất giao
7. Kiểm tra đơn chuyển sang Hoàn thành

---

Cập nhật tài liệu: theo trạng thái code hiện tại của project.