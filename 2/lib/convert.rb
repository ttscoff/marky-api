# frozen_string_literal: true

require_relative "pandoc"

class Convert
  def initialize(input, pandoc: "lib/pandoc", options: {})
    @input = input
    @options = options
    @pandoc = File.expand_path(pandoc)
  end

  def pandoc(opt = {})
    format(:gfm, opt)
  end

  def html(format = :gfm)
    pandoc = PandocRuby.new(@input, from: format, to: :html, wrap: "none")
    pandoc.pandoc_path = @pandoc
    pandoc.convert
  end

  def format(format = :gfm, options: {}, extensions: [])
    opts = {
      from: :html,
      to: "#{format}#{extensions.join}",
      wrap: "none",
    }
    opts.merge!(@options)
    opts.merge!(options)
    pandoc = PandocRuby.new(@input, opts)
    pandoc.pandoc_path = @pandoc
    pandoc.convert
  end
end
