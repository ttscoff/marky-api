# frozen_string_literal: true

module Marky
  class ::Symbol
    MARKDOWN_FORMATS = [:markdown, :markdown_mmd, :markdown_phpextra, :gfm, :commonmark, :commonmark_x, :markdown_strict].freeze

    def markdown?
      MARKDOWN_FORMATS.include?(self)
    end
  end
end
