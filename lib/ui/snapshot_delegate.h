// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

#ifndef FLUTTER_LIB_UI_SNAPSHOT_DELEGATE_H_
#define FLUTTER_LIB_UI_SNAPSHOT_DELEGATE_H_

#include "third_party/skia/include/core/SkImage.h"
#include "third_party/skia/include/core/SkPicture.h"

namespace flutter {

class SnapshotDelegate {
 public:
  struct GpuSnapshot { 
    GpuSnapshot(GrBackendTexture backing_texture, SkColorType color_type, SkAlphaType alpha_type,
                sk_sp<SkColorSpace> color_space, SkImage::BackendTextureReleaseProc texture_release_callback)
                : backing_texture(backing_texture), color_type(color_type), alpha_type(alpha_type),
                color_space(color_space), texture_release_callback(texture_release_callback) {}
    GrBackendTexture backing_texture;
    SkColorType color_type;
    SkAlphaType alpha_type;
    sk_sp<SkColorSpace> color_space;
    SkImage::BackendTextureReleaseProc texture_release_callback;
  };

  virtual sk_sp<SkImage> MakeRasterSnapshot(sk_sp<SkPicture> picture,
                                            SkISize picture_size) = 0;


  virtual sk_sp<SkImage> MakeRasterSnapshotOnHost(sk_sp<SkPicture> picture,
                                                  SkISize picture_size) = 0;

  virtual std::shared_ptr<GpuSnapshot> MakeGpuSnapshot(sk_sp<SkPicture> picture,
                                             SkISize picture_size) = 0;

  virtual sk_sp<SkImage> ConvertToRasterImage(sk_sp<SkImage> image) = 0;
};

}  // namespace flutter

#endif  // FLUTTER_LIB_UI_SNAPSHOT_DELEGATE_H_
