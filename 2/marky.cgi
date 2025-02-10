#!/usr/bin/env ruby

require "cgi"
require "erb"
require "json"
require "logger"
require "nokogiri"
require "rubygems"
require "shellwords"
require "time"
require "uri"

require_relative "lib/string"
require_relative "lib/symbol"
require_relative "lib/htmlentities/htmlentities"
require_relative "lib/readability/lib/readability"
require_relative "lib/convert"
require_relative "lib/cleaner"
require_relative "lib/html2markdown"
require_relative "lib/stackoverflow"
require_relative "lib/github"
require_relative "lib/curl"
require_relative "lib/yui_compressor"

def class_exists?(class_name)
  klass = Module.const_get(class_name)
  klass.is_a?(Class)
rescue NameError
  false
end

if class_exists? "Encoding"
  Encoding.default_external = Encoding::UTF_8 if Encoding.respond_to?("default_external")
  Encoding.default_internal = Encoding::UTF_8 if Encoding.respond_to?("default_internal")
end

# main module
module Marky
  class << self
    # Global logger
    # @return [Logger]
    def log
      @log ||= Logger.new(File.join("logs", Time.now.strftime("%Y-%m-%d.log")))
    end
  end
end

# Main class
module Marky
  class MarkyCGI
    # Markdown formats supported by the API (Pandoc options)
    VALID_FORMATS = %w[json asciidoc asciidoctor beamer commonmark commonmark_x context
                       docbook docbook4 docbook5 dokuwiki fb2 gfm haddock html html5 html4 icml jats_archiving jats_articleauthoring
                       jats_publishing jats jira latex man markdown markdown_mmd markdown_phpextra markdown_strict markua mediawiki
                       ms muse native opendocument org plain rst rtf texinfo textile slideous slidy dzslides revealjs s5
                       tei xwiki zimwiki].freeze

    # Parameters accepted by the API
    # @note can be shortened to just the first letter (or letters required to be unique)
    #
    # url = target url
    # format = markdown format. Accepts any valid format above. (default: gfm)
    # output = output format. Can be complete, html, markdown, or url (default: markdown)
    # readability = use readability (default: false)
    # json = output as json (default: false)
    # link = output as url-encoded link (default: false, can be url (raw encoded), obsidian, nvultra, nvalt, nv, marked)
    # open = open link automatically. If link is greater than 8k, uses Javascript redirect. Requires browser window. (default: false)
    # style = css style to use if outputting as HTML. Can be a Marked style name or a url to lift styles from (forces :complete output) (default: none)
    # import_css = import CSS from linked stylesheets if &style is a url (default: false)
    # complete = output complete HTML page (default: false)
    # inline = use inline links
    VALID_PARAMS = %w[url format output readability json link open style complete import_css inline showframe closewindow debug html title].freeze

    # Valid link types
    VALID_LINKS = %w[url obsidian nvultra nvu nvalt nv marked devonthink dt].freeze

    # Initialize the class
    def initialize
      Marky.log.level = Logger::INFO
      Marky.log.datetime_format = "%Y-%m-%d %H:%M:%S"
      Marky.log.formatter = proc do |severity, datetime, progname, msg|
        "#{datetime} [#{severity}] #{msg}\n#{progname}\n"
      end
      Marky.log.info("Marky started at #{Time.now}")

      @cgi = CGI.new
      sort_params

      @format = @params[:format]&.normalize_format || :markdown_mmd
      @url = @params[:url]
      @readability = @params.key?(:readability) && @params[:readability]
      @json_output = @params.key?(:json) && @params[:json]
      Marky.log.debug("@params: #{@params}")
      @output_format = @params.key?(:output) ? @params[:output].normalize_output_format : :markdown

      @link_type = nil
      if @params[:link]
        VALID_LINKS.each do |l|
          next unless l =~ /^#{@params[:link]}/i

          @link_type = l.to_sym
          @output_format = :url
          break
        end
      end

      @complete = (@params[:complete] && @params[:complete] =~ /^1|t/) || @params.key?(:style) || @output_format == :complete ? true : false

      if @params[:debug]
        Marky.log.level = Logger::DEBUG
        Marky.log.debug("Debugging enabled: #{@url}")
      end
    end

    # Render the output
    #
    # @return [Boolean] true if successful, false otherwise
    def render
      res = start

      if res
        finish
        Marky.log.info("Success: #{@url}")
      else
        Marky.log.error("Failed: #{@url}")
        puts "Error fetching URL"
        return false
      end

      true
    rescue StandardError => e
      Marky.log.error(e.message)
      Marky.log.error(e.backtrace)
      puts e.backtrace
      puts e.message

      false
    ensure
      Marky.log.close
    end

    private

    # Start processing the URL, generate headers, run readability, Pandoc, etc.
    #
    # @note populates @output for use elsewhere
    #
    # @return [Boolean] true if successful, false otherwise
    def start
      puts @cgi.header unless @json_output || @link_type || @output_format == :markdown

      if @params[:html]
        output = @params[:html]
        @title = @params[:title]
        @url = @params[:url]
      else
        curl = Curl.new(@url)
        curled = curl.fetch

        return false unless curled

        unless curled[:meta].nil?
          @keywords = curled[:meta]["keywords"]&.split(/[, ]/) || []
          unless @keywords.empty?
            @keywords = @keywords.map(&:downcase).sort.uniq.delete_if(&:empty?)
          end

          @description = curled[:meta]["description"].sanitize
        end

        output = curled[:body]
        @url = curled[:url]

        return false unless output

        if @url =~ /stack(overflow|exchange)\.com/
          Marky.log.info("StackExchange Page")
          output, @title = StackOverflow.process(output)
        elsif @url =~ %r{gist\.github\.com/[^/]+/[a-z0-9]+(#\S+)?$}
          Marky.log.info("GitHub Gist")
          output, @title = GitHub.processGist(output)
        elsif @url =~ %r{github\.com/[^/]+?/[^/]+?+$}
          Marky.log.info("GitHub Repo")
          output, @title = GitHub.process(output)
        elsif @url =~ %r{github\.com/.*?/\w+\.\w+$}
          Marky.log.info("GitHub file")
          output, @title = GitHub.processFile(output)
        end

        @title ||= curled[:head]&.extract_title&.straighten_quotes
      end

      if @readability
        Marky.log.info("No special urls, running Readability")

        output = Readability::Document.new(output, {
          debug: @params[:debug],
          remove_empty_nodes: true,
          remove_unlikely_candidates: false,
          clean_conditionally: true,
        }).content
      end

      # Random cleanup
      # Finds <div><pre> blocks without nested <code> tags and transforms them
      # 1. Matches <div> with any attributes containing <pre> with any attributes
      # 2. Ensures there's no <code> tag immediately following the <pre>
      # 3. Captures content between <pre> and </pre> tags
      # 4. Strips any <span> tags from the content
      # 5. Escapes HTML special characters in the content
      # 6. Wraps the result in <pre><code> tags
      #
      # Example transformation:
      # Input:  <div class="highlight"><pre>some code</pre></div>
      # Output: <pre><code>some code</code></pre>
      output.gsub!(%r{<div[^>]*><pre[^>]*>[ \n]*(?!<code)(.*?)</pre>[ \n]*</div>}m) do
        m = Regexp.last_match
        "<pre><code>#{CGI.escapeHTML(m[1].gsub(%r{</?span.*?>}, ""))}</code></pre>"
      end

      output.gsub!(/Â/, "\n")

      abs, error = output.absolute_urls(@url) if @url

      if abs
        output = abs
      else
        Marky.log.error("Error generating absolute urls: #{@url}, #{error}")
      end

      parameters = {
        reference_links: @params[:inline] ? "false" : "true",
        reference_location: "block",
        toc: true,
      }

      # Convert HTML to Markdown

      extensions = []

      if @format == :gfm
        extensions << "+alerts"
        extensions << "+autolink_bare_uris"
        extensions << "+definition_lists"
        extensions << "+emoji"
        extensions << "+footnotes"
        extensions << "+gfm_auto_identifiers"
        extensions << "+pipe_tables"
        extensions << "+raw_html"
        extensions << "+strikeout"
        extensions << "+task_lists"
        extensions << "+tex_math_dollars"
        extensions << "+tex_math_gfm"
        extensions << "+yaml_metadata_block"
      elsif @format == :markdown_mmd || @format == :markdown
        extensions << "+backtick_code_blocks"
        extensions << "+blank_before_blockquote"
        extensions << "+blank_before_header"
        extensions << "+definition_lists"
        extensions << "+footnotes"
        extensions << "+markdown_in_html_blocks"
        extensions << "+mmd_header_identifiers"
        extensions << "+mmd_link_attributes"
        extensions << "+mmd_title_block"
        extensions << "+raw_html"
        extensions << "+subscript"
        extensions << "+superscript"
        extensions << "+table_captions"
      end

      # Remove iframes and replace with placeholders
      iframes = output.to_enum(:scan, %r{<iframe[^>]*src="([^"]*)"[^>]*>.*?</iframe>}m).map { Regexp.last_match }
      iframes.each_with_index do |iframe, idx|
        output.sub!(/#{Regexp.escape(iframe[0])}/, "%%iframe-#{idx}%%")
      end

      # Convert to Markdown
      fmt = VALID_FORMATS.include?(@format.to_s) ? @format : :markdown_mmd
      output = Convert.new(output).format(fmt, extensions: extensions, options: parameters)

      # restore iframes
      iframes.each_with_index do |iframe, idx|
        output.sub!("%%iframe-#{idx}%%", iframe[0])
      end

      # Clean up conversion output
      output = MarkdownCleaner.new(output).clean

      # Flip reference links to inline links
      unless @params[:inline]
        links = output.to_enum(:scan, /^  \[(?!\])(?<title>.*?)\]: (?=\S)/).map { Regexp.last_match }

        # counter = output.scan(/^ *\[(\d+)\]: (?=\S)/).flatten.map(&:to_i).max + 1 || 1
        counter = 1
        links.each do |link|
          output.sub!(/^( *)\[#{Regexp.escape(link["title"])}\]: (?=\S)/, "\\1[%%#{counter}]: ")

          output.gsub!(/\]\[#{Regexp.escape(link["title"])}\]/, "][%%#{counter}]")
          output.gsub!(/\[#{Regexp.escape(link["title"])}\](?=[^\[(:])/) do
            m = Regexp.last_match

            if m[0] =~ /\[\d+\]/
              "[%%#{counter}]"
            else
              "[#{link["title"]}][%%#{counter}]"
            end
          end
          counter += 1
        end
        Marky.log.debug("Flipped #{counter} links")
        output.gsub!(/\[%%(\d+)\]/, '[\1]')
      end

      if output.length.positive?
        Marky.log.info("Processed URL: #{@url}")
      else
        Marky.log.error("Error processing URL: #{@url}")
        return false
      end

      # Add title to Markdown output and sanitize
      @output = @format.markdown? ? add_title(output.sanitize) : output.sanitize

      # Remove typographically-correct m-dash if not multimarkdown
      @output = @output.gsub(/\b *--- *\b/, '--') if @format != :markdown_mmd

      true
    rescue StandardError => e
      Marky.log.error("Error processing URL: #{@url}, #{e} #{e.backtrace}")
      false
    end

    # Add source link and title to Markdown output
    #
    # @param [String] output the output to add the title to
    # @return [String] the output with the title added
    def add_title(output)
      return output unless @params[:readability]

      meta = {}
      meta[:title] = %("#{@title.gsub(/"/, "\\\"")}") if @title
      meta[:source] = @url if @url
      meta[:date] = Time.now.strftime("%Y-%m-%d %H:%M")
      if @keywords
        if @format == :gfm
          meta[:tags] = %([#{@keywords.join(", ")}])
        else
          meta[:tags] = @keywords.join(", ")
        end
      end

      if @description
        meta[:description] = @format == :gfm ? ">\n  #{@description}" : @description
      end

      if @format == :gfm
        @metadata = <<~METADATA
          ---
          #{meta.map { |k, v| "#{k}: #{v}" }.join("\n")}
          ---
        METADATA
      elsif @format == :markdown_mmd
        @metadata = <<~METADATA
          #{meta.map { |k, v| "#{k}: #{v}" }.join("\n")}
        METADATA
      end

      if output =~ /^# (.*)$/
        output.sub!(/^# (.*)$/, "")
        @title = Regexp.last_match[1]
      end

      source = @url.nil? ? "" : "\n[source](#{@url})"
      title = @title.nil? ? "" : "\n# #{@title.gsub(%r{/}, ":").strip}\n"

      <<~RESULT
        #{@metadata}
        #{source}
        #{title}
        #{output.strip}
      RESULT
    end

    # Finish output, outputting HTML frame if needed
    def finish
      if @complete
        puts "<!DOCTYPE html>"
        puts "<html lang=\"en\"><head>"
        puts style if @params.key?(:style)
        puts '<meta charset="utf-8">'
        puts "<title>#{@title}</title>"
        puts "</head><body><script>0</script>"
        puts '<div id="wrapper">' if @params.key?(:style)
        out
        puts "</div>" if @params.key?(:style)
        puts "</body></html>"
      else
        out
      end
    end

    # Embed a style tag with compressed CSS
    def style
      return "" unless @params.key?(:style)

      css_style = @params[:style]
      return "" unless css_style

      Dir.glob(File.join(File.expand_path("styles"), "*.css")).each do |f|
        if File.basename(f) =~ /#{css_style}/i
          css_style = f
          break
        end
      end

      if File.exist?(css_style)
        css = IO.read(css_style)

        "<style>#{css}</style>"
      elsif css_style.url?
        curl = Curl.new(css_style)

        curled = curl.fetch
        if curled
          stylesheets = curl.stylesheets
          links = []
          stylesheets.each do |s|
            links << if @params[:import_css]
              import_css(s)
            else
              %(<link rel="stylesheet" type="text/css" href="#{s}">)
            end
          end
          inline_styles = curl.inline_styles

          links << "<style>#{inline_styles}</style>" if inline_styles

          links.join("\n")
        else
          ""
        end
      else
        ""
      end
    rescue StandardError => e
      Marky.log.error("Error processing style: #{e.message}")
    end

    def import_css(url)
      content = Curl.new(url).fetch
      if content
        css = content[:source]
        css.absolute_urls!(url)
        "<style>#{css}</style>"
      else
        Marky.log.error("Error importing CSS: #{url}")
        %(<link rel="stylesheet" type="text/css" href="#{s}">)
      end
    end

    def compress_css(css)
      YuiCompressor::Yui.compress(css)
    end

    # Generate the output content to be included between #start and #finish
    def out
      # If outputting to JSON, generate and output JSON with mime type
      if @json_output
        @cgi.out("application/json") { jsonify }
        return
      end

      # If output is to a link, generate the link and optionally open (with :open)
      unless @link_type.nil?
        link = to_link.strip
        if @params[:open].to_s =~ /^1|t/ && @link_type != :url
          if link.length < 8000 && !@params[:closewindow]
            # puts @cgi.header('status' => 'REDIRECT', 'location' => link)
            buf = " " * 4096
            @cgi.out("status" => "REDIRECT", "connection" => "close", "location" => link) { buf }
            sleep 10
          else
            @cgi.out("text/html") { redirect(link) }
          end
        else
          @cgi.out("text/plain") { link }
        end

        return
      end

      if @complete
        puts @output.to_html(@format)
        return
      end

      case @output_format
      when :html, :complete
        puts @output.to_html(@format)
      when :url
        @cgi.out("text/plain") { to_link }
      else
        @cgi.out("text/plain") { @output }
      end
    end

    def redirect(url)
      <<~ENDHTML
        <html>
        <head>
          <meta http-equiv="refresh" content="0;url=#{url}" />
          <title></title>
        </head>
        <body>#{close_script}</body>
        </html>
      ENDHTML
    end

    def close_script
      return "" unless @params[:closewindow]

      <<~ENDSCRIPT
        <script>window.close();</script>
      ENDSCRIPT
    end

    def to_link
      out_url = ERB::Util.url_encode(@output)
      title = @title.nil? ? "Unknown" : ERB::Util.url_encode(@title.gsub(%r{/}, ":").strip)

      case @link_type
      when :url
        out_url
      when :obsidian
        "obsidian://new?name=#{title}&content=#{out_url}"
      when :nv
        "nv://make?title=#{title}&txt=#{out_url}"
      when :nvalt
        "nvalt://make?title=#{title}&txt=#{out_url}"
      when :nvu, :nvultra
        "x-nvultra://make?title=#{title}&txt=#{out_url}"
      when :marked
        "x-marked://preview?text=#{out_url}"
      when :dt, :devonthink
        "x-devonthink://createMarkdown?title=#{title}&text=#{out_url}"
      end
    end

    def jsonify
      output = { "title" => @title, "url" => @url, "markup" => @output, "html" => Convert.new(@output).html(@format) }
      output["link"] = to_link if @link_type
      output.to_json
    end

    def h1(content)
      puts "<h1>#{content}</h1>"
    end

    def para(content)
      puts "<p>#{content}</p>"
    end

    def pre(content)
      puts "<pre><code>#{content}</code></pre>"
    end

    def sort_params
      @params = {}
      @cgi.params.each do |k, v|
        key = nil
        VALID_PARAMS.each do |p|
          if p =~ /#{k}/i
            key = p.to_sym
            break
          end
        end

        next unless key

        value = if v.first == "1" || v.first == "true"
            true
          elsif v.first == "0" || v.first == "false"
            false
          else
            CGI.unescape(v.first)
          end
        @params[key] = value
      end
    end
  end
end

marky = Marky::MarkyCGI.new
marky.render
