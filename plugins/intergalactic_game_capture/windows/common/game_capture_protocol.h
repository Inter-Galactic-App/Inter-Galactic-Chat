#pragma once

#include <cstdint>

namespace intergalactic_game_capture {

constexpr uint32_t kProtocolMagic = 0x43474749u;  // IGGC little-endian.
constexpr uint16_t kProtocolVersion = 2;
constexpr int kRingDepth = 3;
constexpr int kDefaultDurationMs = 10000;
constexpr int kMaxDurationMs = 60 * 60 * 1000;
constexpr int kDefaultSavedFrames = 5;
constexpr int kMaxSavedFrames = 30;
constexpr int kDefaultHostProofFrames = 0;
constexpr int kMaxHostProofFrames = 10;
constexpr int kDefaultPublicationHandoffMaxWidth = 1280;
constexpr int kDefaultPublicationHandoffMaxHeight = 720;
constexpr int kDefaultPublicationHandoffTargetFps = 30;
constexpr int kMinPublicationHandoffTargetFps = 1;
constexpr int kMaxPublicationHandoffTargetFps = 60;
constexpr int kDefaultPublicationHandoffProofFrames = 0;
constexpr int kMaxPublicationHandoffProofFrames = 10;
constexpr uint32_t kSharedTextureStateVersion = 2;

constexpr const wchar_t* kDefaultResultsRoot =
    L"runtime\\game-capture-poc\\results";

enum class AttachStatus {
  kUnknown,
  kAttached,
  kNoTargetPid,
  kUnsupportedArchitecture,
  kBlockedByProcessSecurity,
  kInjectFailed,
  kTimedOut,
  kStopped,
};

enum class CaptureBackend : uint32_t {
  kUnknown = 0,
  kD3D11PresentHook = 1,
  kVulkan = 2,
  kD3D12 = 3,
  kOpenGL = 4,
};

enum class SourceFormat : uint32_t {
  kUnknown = 0,
  kBgra8 = 1,
  kRgba8 = 2,
  kR10G10B10A2 = 3,
  kNv12 = 4,
  kP010 = 5,
  kOther = 255,
};

enum class ColorSpace : uint32_t {
  kUnknown = 0,
  kSdr = 1,
  kHdr10 = 2,
};

enum class SyncKind : uint32_t {
  kUnknown = 0,
  kNone = 1,
  kEvent = 2,
  kKeyedMutex = 3,
  kFence = 4,
  kSemaphore = 5,
};

enum class FrameReadyState : uint32_t {
  kUnknown = 0,
  kEmpty = 1,
  kReady = 2,
  kStale = 3,
  kFailed = 4,
};

enum class FailureReason : uint32_t {
  kNone = 0,
  kUnsupportedProtectedTarget = 1,
  kUnsupportedFormat = 2,
  kSharedTextureUnavailable = 3,
  kSyncTimeout = 4,
  kDeviceLost = 5,
  kConversionFailed = 6,
  kEncoderNotAccepting = 7,
  kAttachFailed = 8,
};

inline const char* AttachStatusName(AttachStatus status) {
  switch (status) {
    case AttachStatus::kAttached:
      return "attached";
    case AttachStatus::kNoTargetPid:
      return "no_target_pid";
    case AttachStatus::kUnsupportedArchitecture:
      return "unsupported_architecture";
    case AttachStatus::kBlockedByProcessSecurity:
      return "blocked_by_process_security";
    case AttachStatus::kInjectFailed:
      return "inject_failed";
    case AttachStatus::kTimedOut:
      return "timed_out";
    case AttachStatus::kStopped:
      return "stopped";
    case AttachStatus::kUnknown:
    default:
      return "unknown";
  }
}

inline const char* CaptureBackendName(CaptureBackend backend) {
  switch (backend) {
    case CaptureBackend::kD3D11PresentHook:
      return "d3d11";
    case CaptureBackend::kVulkan:
      return "vulkan";
    case CaptureBackend::kD3D12:
      return "d3d12";
    case CaptureBackend::kOpenGL:
      return "opengl";
    case CaptureBackend::kUnknown:
    default:
      return "unknown";
  }
}

inline const char* SourceFormatName(SourceFormat format) {
  switch (format) {
    case SourceFormat::kBgra8:
      return "bgra8";
    case SourceFormat::kRgba8:
      return "rgba8";
    case SourceFormat::kR10G10B10A2:
      return "r10g10b10a2";
    case SourceFormat::kNv12:
      return "nv12";
    case SourceFormat::kP010:
      return "p010";
    case SourceFormat::kOther:
      return "other";
    case SourceFormat::kUnknown:
    default:
      return "unknown";
  }
}

inline const char* ColorSpaceName(ColorSpace color_space) {
  switch (color_space) {
    case ColorSpace::kSdr:
      return "sdr";
    case ColorSpace::kHdr10:
      return "hdr10";
    case ColorSpace::kUnknown:
    default:
      return "unknown";
  }
}

inline const char* SyncKindName(SyncKind sync_kind) {
  switch (sync_kind) {
    case SyncKind::kNone:
      return "none";
    case SyncKind::kEvent:
      return "event";
    case SyncKind::kKeyedMutex:
      return "keyed_mutex";
    case SyncKind::kFence:
      return "fence";
    case SyncKind::kSemaphore:
      return "semaphore";
    case SyncKind::kUnknown:
    default:
      return "unknown";
  }
}

inline const char* FrameReadyStateName(FrameReadyState state) {
  switch (state) {
    case FrameReadyState::kEmpty:
      return "empty";
    case FrameReadyState::kReady:
      return "ready";
    case FrameReadyState::kStale:
      return "stale";
    case FrameReadyState::kFailed:
      return "failed";
    case FrameReadyState::kUnknown:
    default:
      return "unknown";
  }
}

inline const char* FailureReasonName(FailureReason reason) {
  switch (reason) {
    case FailureReason::kNone:
      return "none";
    case FailureReason::kUnsupportedProtectedTarget:
      return "unsupported_protected_target";
    case FailureReason::kUnsupportedFormat:
      return "unsupported_format";
    case FailureReason::kSharedTextureUnavailable:
      return "shared_texture_unavailable";
    case FailureReason::kSyncTimeout:
      return "sync_timeout";
    case FailureReason::kDeviceLost:
      return "device_lost";
    case FailureReason::kConversionFailed:
      return "conversion_failed";
    case FailureReason::kEncoderNotAccepting:
      return "encoder_not_accepting";
    case FailureReason::kAttachFailed:
      return "attach_failed";
    default:
      return "unknown";
  }
}

inline SourceFormat SourceFormatFromDxgiFormat(uint32_t dxgi_format) {
  switch (dxgi_format) {
    case 24:   // DXGI_FORMAT_R10G10B10A2_UNORM
      return SourceFormat::kR10G10B10A2;
    case 28:   // DXGI_FORMAT_R8G8B8A8_UNORM
    case 29:   // DXGI_FORMAT_R8G8B8A8_UNORM_SRGB
      return SourceFormat::kRgba8;
    case 87:   // DXGI_FORMAT_B8G8R8A8_UNORM
    case 88:   // DXGI_FORMAT_B8G8R8X8_UNORM
    case 91:   // DXGI_FORMAT_B8G8R8A8_UNORM_SRGB
    case 93:   // DXGI_FORMAT_B8G8R8X8_UNORM_SRGB
      return SourceFormat::kBgra8;
    case 103:  // DXGI_FORMAT_NV12
      return SourceFormat::kNv12;
    case 104:  // DXGI_FORMAT_P010
      return SourceFormat::kP010;
    case 0:    // DXGI_FORMAT_UNKNOWN
      return SourceFormat::kUnknown;
    default:
      return SourceFormat::kOther;
  }
}

struct SharedTextureSlotState {
  uint64_t shared_handle = 0;
  uint64_t frame_index = 0;
  uint32_t width = 0;
  uint32_t height = 0;
  uint32_t dxgi_format = 0;
  uint32_t sample_count = 1;
};

struct SharedTextureState {
  uint32_t magic = kProtocolMagic;
  uint32_t version = kSharedTextureStateVersion;
  uint32_t ring_depth = kRingDepth;
  uint32_t latest_slot_index = 0;
  uint64_t generation = 0;
  uint64_t latest_frame_index = 0;
  uint64_t latest_qpc = 0;
  uint64_t present_count = 0;
  uint64_t copied_frames = 0;
  uint64_t dropped_frames = 0;
  uint64_t overwritten_frames = 0;
  uint32_t backbuffer_width = 0;
  uint32_t backbuffer_height = 0;
  uint32_t backbuffer_format = 0;
  uint32_t sample_count = 1;
  uint32_t shared_texture_supported = 0;
  uint32_t reserved = 0;
  SharedTextureSlotState slots[kRingDepth];
  uint32_t source_api = static_cast<uint32_t>(CaptureBackend::kUnknown);
  uint32_t source_format = static_cast<uint32_t>(SourceFormat::kUnknown);
  uint32_t color_space = static_cast<uint32_t>(ColorSpace::kUnknown);
  uint32_t hdr_flags = 0;
  uint32_t sync_kind = static_cast<uint32_t>(SyncKind::kUnknown);
  uint32_t ready_state = static_cast<uint32_t>(FrameReadyState::kUnknown);
  uint32_t failure_reason = static_cast<uint32_t>(FailureReason::kNone);
  uint32_t contract_reserved = 0;
};

}  // namespace intergalactic_game_capture
