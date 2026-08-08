# Nhật ký thay đổi

Mọi thay đổi đáng chú ý của dự án được ghi lại trong file này.

Định dạng dựa trên [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
và dự án tuân theo [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-08-09

### Đã thêm

- Phát hành công khai đầu tiên.
- `wsl-safe-backup-restore.ps1`:
  - Chế độ `BACKUP ONLY` — xuất bản lưu trữ VHDX độc lập có timestamp mà không unregister distro.
  - Chế độ `SAFE MOVE / RESTORE` — bản lưu trữ + xuất VHDX live, xác minh kép, chuỗi xác nhận tường minh, unregister, `--import-in-place`, xác minh đăng ký/boot và khôi phục distro mặc định.
  - Kiểm tra trước khi chạy: khả dụng WSL, tồn tại distro, xác nhận WSL2, phát hiện/kiểm tra sơ bộ VHDX, thử quyền ghi và kiểm tra dung lượng trống với hệ số an toàn có thể cấu hình.
  - Kiểm tra khả năng `--export --vhd` và `--import-in-place`.
  - In hướng dẫn phục hồi nếu unregister hoặc import thất bại.
- `run-wsl-safe.cmd`:
  - Launcher chạy kiểm tra cú pháp PowerShell trước khi thực thi và từ chối chạy script khi xác thực cú pháp thất bại.
- Tài liệu: README, CONTRIBUTING, SECURITY, CODE_OF_CONDUCT và bản phân tích sâu mô hình an toàn tại `docs/SAFETY_MODEL.md`.
- Bản dịch tiếng Việt cho toàn bộ tài liệu (các file `*.vi.md`).
- Bộ công cụ kiểm tra: `npm run validate` phân tích mọi sơ đồ Mermaid, xác minh code fence và link nội bộ trong Markdown, đồng thời chạy kiểm tra cú pháp PowerShell mà không thực thi script (`scripts/validate-docs.mjs`, `scripts/validate-ps1.mjs`, `scripts/validate-ps1.ps1`).
- Git hooks qua lefthook: `pre-commit` (tài liệu + PowerShell), `commit-msg` (commitlint / Conventional Commits), `pre-push` (toàn bộ bộ CI).
- GitHub Actions CI: kiểm tra tài liệu, kiểm tra đồng bộ tài liệu Anh / Việt, kiểm tra cú pháp PowerShell trên Windows, và commitlint trên pull request.
