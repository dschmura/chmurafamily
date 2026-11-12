class ApplicationRecord < ActiveRecord::Base
  primary_abstract_class

  # Wider than ActiveStorage.web_image_content_types: HEIC/HEIF (the iPhone camera default) stay in.
  # One list for every image attachment, not per-model copies; see /docs/developer/security.
  IMAGE_CONTENT_TYPES = %w[
    image/png
    image/jpeg
    image/gif
    image/webp
    image/heic
    image/heif
  ].freeze
end
