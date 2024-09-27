# frozen_string_literal: true

module Marky
  # String helpers
  class ::String
    def url?
      url = dup
      # url = "https://#{url}" if url !~ %r{^https?://}i
      url =~ /\A#{URI::DEFAULT_PARSER.make_regexp}\z/ ? true : false
    end

    def path?
      self =~ %r{^/|\.\.?/} ? true : false
    end

    def fragment?
      self =~ /^#/ ? true : false
    end

    def resolve_path(base = "/")
      File.expand_path(self, base)
    end

    def normalize_format
      case self
      when /^(markdown|md|mmd)$/
        :markdown_mmd
      else
        if Marky::VALID_FORMATS.include?(self)
          to_sym
        else
          :gfm
        end
      end
    end

    def normalize_output_format
      case self
      when /^c/
        :complete
      when /^h/
        :html
      when /^[lu]/
        :url
      else
        :markdown
      end
    end

    def extract_title
      doc = Nokogiri::HTML(self)
      title = doc.at_css("title").text
      title = title.gsub(/\s+/, " ").strip
      HTMLEntities.new.decode(title)
    end

    def to_html(fmt = :gfm)
      Convert.new(self).html(fmt)
    end

    def remove_empty_links
      gsub(/\[([^\]]+)\]\(\s*\)/, "\1").gsub(/(?<!!)\[\s*\]\[[^\]]+\]/, "").gsub(/(?<!!)\[\s*\]\([^\)]+\)/, "")
    end

    def sanitize
      HTMLEntities.new.decode(self).straighten_quotes.remove_empty_links
    end

    def straighten_quotes
      codes = ["\xe2\x80\x98", "\xe2\x80\x99", "\xe2\x80\x9c", "\xe2\x80\x9d", "\xe2\x80\x93", "\xe2\x80\x94",
               "\xe2\x80\xa6"]
      ascii = ["'", "'", '"', '"', "-", "--", "..."]

      gsub(/“|”/, '"').gsub(/‘|’/, "'")
        .gsub(/&#8220;|&#8221;/, '"').gsub(/&#8216;|&#8217;/, "'")
        .gsub(/&ldquo;|&rdquo;/, '"').gsub(/&lsquo;|&rsquo;/, "'")
        .gsub(/&quot;/, '"').gsub(/&apos;/, "'")
        .gsub(/(#{codes.join("|")})/).with_index { |_m, i| ascii[i] }
    end

    def absolute_urls(base_url)
      uri = URI(base_url)
      host = uri.host
      scheme = uri.scheme
      path = uri.path =~ %r{/$} ? uri.path.resolve_path : File.dirname(uri.path)
      path = "/" if path == "."
      base = URI("#{scheme}://#{host}#{path}")

      out = []

      gsub!(/url\(['"]?(.*?)['"]?\)/) do
        m = Regexp.last_match

        if m[1].fragment?
          URI.join(uri, m[1]).to_s
        elsif !m[1].url? && !m[1].path?
          m[1]
        else
          m[1] =~ %r{^(\w+:)?//} ? m[1] : URI.join(base, m[1]).to_s
        end
      end

      gsub!(/(?<=href=['"])(?!http)(.*?)(?=["'])/) do
        m = Regexp.last_match
        begin
          URI.join(base, m[1]).to_s
        rescue StandardError
          m[1]
        end
      end

      gsub(/(?<=src=['"])(?!http)(.*?)(?=["'])/) do
        m = Regexp.last_match
        m[1].url? ? URI.join(base, m[1]).to_s : m[1]
      end
    rescue StandardError => e
      puts e.backtrace
      puts e
      exit
      [false, e]
    end

    def absolute_urls!(base_url)
      replace(absolute_urls(base_url))
    end
  end
end
