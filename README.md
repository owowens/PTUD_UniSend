# UniSend - Tài liệu UI/UX và logic Order hiện tại

Tài liệu này mô tả trạng thái code hiện tại của ứng dụng, tập trung vào:

1. Logic user id
2. Logic màn hình đơn hàng
3. Cách UI ràng buộc thao tác theo dữ liệu

Phạm vi tài liệu: chỉ mô tả UI/UX và logic hiển thị trên ứng dụng. Không chỉnh sửa và không mở rộng phần Firebase.

## 1. Tổng quan giao diện

Ứng dụng dùng Material 3, hỗ trợ theme sáng/tối, và điều hướng chính qua 4 tab:

1. Bản đồ
2. Đơn hàng
3. Trò chuyện
4. Hồ sơ

Luồng vào app:

1. Nếu xác thực sẵn sàng: theo luồng đăng nhập bình thường.
2. Nếu chạy bypass/UI-only: vào thẳng màn hình chính để thao tác giao diện.

## 2. Trạng thái dữ liệu đơn hàng hiện tại

Đã xóa toàn bộ dữ liệu test seed sẵn trong service đơn hàng.

Hệ quả hiện tại:

1. Màn danh sách đơn khởi tạo rỗng.
2. Đơn mới xuất hiện khi người dùng tạo đơn từ form tạo đơn.
3. Không còn bộ ORD-DEMO hoặc danh sách user demo được nạp sẵn khi khởi động.

## 3. Logic user id hiện tại

### 3.1 Nguồn current user

`current_user_id` được lấy theo thứ tự:

1. UID Firebase nếu có phiên đăng nhập.
2. Nếu không có phiên đăng nhập, dùng định danh local trung tính là `local_user`.

### 3.2 Khi tạo đơn

Form tạo đơn hỗ trợ 2 trường hợp:

1. Tạo đơn thường: người dùng hiện tại là người gửi.
2. Tạo đơn hộ: cho phép nhập người gửi khác.

Luôn lưu thêm `created_by` bằng người dùng hiện tại để truy vết người tạo thao tác.

### 3.3 Về ảnh đơn

Ảnh trong giai đoạn hiện tại phục vụ hiển thị UI và không dùng để gán quyền thao tác đơn hàng.

## 4. Logic phân quyền thao tác Order

### 4.1 Suy ra vai trò động từ dữ liệu

Không gán vai trò cố định cho user. Vai trò được suy ra động bằng cách so sánh `current_user_id` với:

1. `sender_id`
2. `receiver_id`
3. `carrier_id`
4. `created_by`

### 4.2 Điều kiện hiển thị và cho phép thao tác

Mỗi thao tác được ràng buộc bởi 3 lớp dữ liệu:

1. Vai trò suy ra từ id (ai được phép nhìn thấy nút).
2. Trạng thái đơn (`order_status`).
3. Cờ backend-style trên đơn (`canAccept`, `canMarkDelivered`, `canCancel`).

Hành vi UI:

1. Nếu không hợp lệ theo role hoặc trạng thái: ẩn nút.
2. Nếu hợp lệ nhưng backend từ chối: hiện nút ở trạng thái disable và ưu tiên hiển thị lý do từ chối.

## 5. Trình bày Order Card hiện tại

Order Card đã được tối giản theo hướng dễ đọc:

1. Chỉ hiển thị 1 trạng thái chính cho mỗi đơn.
2. Không hiển thị trực tiếp các field kỹ thuật như `created_by`, `sender_id`, `receiver_id`, `carrier_id`.
3. Chỉ giữ 1 thông điệp ngắn theo ngữ cảnh vai trò và trạng thái.
4. Ưu tiên nhận diện bằng màu sắc và icon thay vì nhiều dòng chữ.

## 6. Tóm tắt luồng thao tác hiện tại

1. Vào app và chọn tab Đơn hàng.
2. Nếu chưa có dữ liệu, màn hình hiển thị empty state theo từng trạng thái.
3. Tạo đơn từ tab Bản đồ qua form tạo đơn.
4. Quay lại tab Đơn hàng để theo dõi và thao tác theo quyền được suy ra từ dữ liệu.

## 7. Ghi chú phạm vi

Tài liệu này được cập nhật theo logic code hiện tại và việc loại bỏ dữ liệu test đã thêm, không thay đổi phần Firebase.
