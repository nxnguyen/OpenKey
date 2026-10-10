# OpenKey macOS: phục hồi Telex sau khi máy bị chậm

Fork: https://github.com/nxnguyen/OpenKey

## Nguyên nhân và bản sửa

OpenKey dùng một active Quartz event tap để nhận và chuyển đổi phím.
Khi callback phản hồi quá chậm, macOS có thể tắt tap và gửi thông báo
`kCGEventTapDisabledByTimeout`. Áp lực RAM/swap hoặc CPU có thể gây độ trễ
này. Trên upstream master, callback bỏ qua thông báo và chỉ bật tap lúc
khởi tạo. Vì vậy app và biểu tượng V vẫn tồn tại nhưng không còn chuyển
đổi Telex cho đến khi khởi động lại.

Bản sửa xử lý thông báo timeout và `kCGEventTapDisabledByUserInput` trước
khi đọc dữ liệu phím, bật lại tap đang được manager sở hữu, rồi trả về.
Sau khi manager dừng, thông báo đến muộn không bật lại tap đã giải phóng.

Đưa bản sửa từ [PR #332 của Duy Huynh](https://github.com/tuyenvm/OpenKey/pull/332)
vào fork bằng cherry-pick, giữ thông tin tác giả.

Tài liệu chính thức:

- [CGEventTapEnable](https://developer.apple.com/documentation/coregraphics/cgevent/tapenable(tap:enable:))
- [kCGEventTapDisabledByTimeout](https://developer.apple.com/documentation/coregraphics/cgeventtype/tapdisabledbytimeout)

Đây là lỗi có thể tái hiện trong mã nguồn và rất khớp triệu chứng được báo.
Chưa thu được trạng thái tap đúng lúc sự cố thiếu RAM trên máy người dùng,
nên chưa thể loại trừ những nguyên nhân khác như Secure Input hoặc mất
quyền Accessibility. Bản sửa không giúp app tự sống lại nếu hệ điều hành
đã kết thúc hoàn toàn tiến trình.

## Kiểm thử và build

```sh
bash tests/macOS/run-event-tap-tests.sh
bash scripts/build-macos-recovery.sh /path/to/new-output-directory
```

Kiểm thử liên kết các object thật của manager, callback, UI và engine từ
bản build Release. Chỉ thay thế ranh giới Quartz event tap bằng fake để
không gửi phím vào ứng dụng đang dùng và không cần quyền Accessibility.
Kiểm tra chuyển `as` thành `á`, thông báo timeout/user-input lặp lại ba lần,
phím tiếng Việt sau phục hồi trên cùng tiến trình, sự kiện không liên quan
và thông báo đến sau khi dừng. Kiểm thử trước patch thất bại ở phục hồi và
Telex sau phục hồi; sau patch mọi kiểm tra đều thành công.

Không cố tình làm đầy RAM của máy. Kiểm thử mô phỏng thông báo vô hiệu hóa;
chưa thực hiện kiểm thử timeout thật của WindowServer vì tiến trình chạy
kiểm thử chưa có quyền Accessibility/Input Monitoring.

Bản đóng gói là **2.0.6, build 50**, dành cho **macOS 12 trở lên**, gồm
**arm64 và x86_64**, kèm login helper được build từ mã nguồn. Đây là số
phiên bản riêng của fork, không phải bản phát hành chính thức của tác giả.
Build 50 cao hơn bản chính thức 2.0.5/build 49 để trình kiểm tra cập nhật
hiện tại không đề nghị quay lại bản cũ. Chữ ký ad hoc dành cho bản tự build,
không có Developer ID/notarization của tác giả gốc.

## Thay ứng dụng

1. Thoát OpenKey qua menu của app.
2. Sao lưu `/Applications/OpenKey.app` ra một thư mục riêng để có thể quay lại.
3. Giải nén ZIP, chép `OpenKey.app` mới vào `/Applications`, thay bản cũ.
4. Mở **System Settings → Privacy & Security → Accessibility**, xóa mục
   OpenKey cũ nếu quyền không được nhận, thêm `/Applications/OpenKey.app`
   mới và bật quyền. Không cần xóa cấu hình Telex hoặc gõ tắt.
5. Mở OpenKey, chọn V/Telex, thử `tieengs Vieetj` → `tiếng Việt`.
6. Nếu Gatekeeper chặn bản tải về, dùng **Privacy & Security → Open Anyway**.

Nếu cần quay lại, thoát OpenKey, chép bundle đã sao lưu về `/Applications`
và cấp lại quyền Accessibility cho bản đó.

Nếu lỗi vẫn lặp lại, đọc trạng thái tap bằng `CGGetEventTapList`: lọc
`tappingProcess` theo PID OpenKey và kiểm tra `enabled`. Tap vẫn bật nhưng
không nhận phím có thể liên quan đến Secure Input; không được tự tắt cơ
chế bảo vệ này. Không ghi lại nội dung phím để chẩn đoán.

OpenKey gốc của Mai Vũ Tuyên, phân phối theo GPL-3.0; xem `LICENSE` và mã
nguồn fork khi chia sẻ bản sửa.
