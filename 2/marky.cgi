#!/usr/bin/env ruby

require 'cgi'
require 'erb'
require 'json'
require 'logger'
require 'nokogiri'
require 'rubygems'
require 'shellwords'
require 'time'
require 'uri'

require_relative 'lib/string'
require_relative 'lib/htmlentities/htmlentities'
require_relative 'lib/readability/lib/readability'
require_relative 'lib/convert'
require_relative 'lib/cleaner'
require_relative 'lib/html2markdown'
require_relative 'lib/stackoverflow'
require_relative 'lib/github'
require_relative 'lib/curl'
require_relative 'lib/yui_compressor'

def class_exists?(class_name)
  klass = Module.const_get(class_name)
  klass.is_a?(Class)
rescue NameError
  false
end

if class_exists? 'Encoding'
  Encoding.default_external = Encoding::UTF_8 if Encoding.respond_to?('default_external')
  Encoding.default_internal = Encoding::UTF_8 if Encoding.respond_to?('default_internal')
end

# Main class
module Marky
  class Marky
    # Markdown formats supported by the API (Pandoc options)
    VALID_FORMATS = %w[json asciidoc asciidoctor beamer biblatex bibtex chunkedhtml commonmark commonmark_x context csljson
                       docbook docbook4 docbook5 dokuwiki fb2 gfm haddock html html5 html4 icml ipynb jats_archiving jats_articleauthoring
                       jats_publishing jats jira latex man markdown markdown_mmd markdown_phpextra markdown_strict markua mediawiki
                       ms muse native opml opendocument org pdf plain pptx rst rtf texinfo textile slideous slidy dzslides revealjs s5
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
    VALID_PARAMS = %w[url format output readability json link open style complete import_css].freeze

    # Valid link types
    VALID_LINKS = %w[url obsidian nvultra nvalt nv marked].freeze

    # Initialize the class
    def initialize
      @log = Logger.new(File.join('logs', Time.now.strftime('%Y-%m-%d.log')))
      @log.level = Logger::INFO
      @log.datetime_format = '%Y-%m-%d %H:%M:%S'
      @log.formatter = proc do |severity, datetime, _progname, msg|
        "#{datetime} [#{severity}] #{msg}\n"
      end

      @cgi = CGI.new
      sort_params

      @format = @params[:format]&.normalize_format || :gfm
      @url = @params[:url]
      @readability = @params.key?(:readability) && @params[:readability]
      @json_output = @params.key?(:json) && @params[:json]
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
    end

    # Render the output
    #
    # @return [Boolean] true if successful, false otherwise
    def render
      res = start

      if res
        finish
        @log.info("Success: #{@url}")
      else
        @log.error("Failed: #{@url}")
        puts 'Error fetching URL'
        return false
      end

      true
    rescue StandardError => e
      @log.error(e.message)
      puts e.backtrace
      puts e.message

      false
    ensure
      @log.close
    end

    private

    # Start processing the URL, generate headers, run readability, Pandoc, etc.
    #
    # @note populates @output for use elsewhere
    #
    # @return [Boolean] true if successful, false otherwise
    def start
      puts @cgi.header unless @json_output || @link_type
      curl = Curl.new(@url)
      curled = curl.fetch

      return false unless curled

      output = curled[:body]

      return false unless output

      if @url =~ /stack(overflow|exchange)\.com/
        output, @title = StackOverflow.process(output)
      elsif @url =~ %r{github\.com/\S+/\S+$}
        output, @title = GitHub.process(output)
      elsif @readability
        output = Readability::Document.new(output, {
                                             remove_empty_nodes: true,
                                             remove_unlikely_candidates: false,
                                             clean_conditionally: true
                                           }).content
      end

      @title ||= curled[:head]&.extract_title&.straighten_quotes

      # Random cleanup
      output.gsub!(%r{<div[^>]*><pre[^>]*>[ \n]*(?!<code)(.*?)</pre>[ \n]*</div>}m) do
        m = Regexp.last_match
        "<pre><code>#{CGI.escapeHTML(m[1].gsub(%r{</?span.*?>}, ''))}</code></pre>"
      end

      output.gsub!(/Â/, "\n")

      abs, error = output.absolute_urls(@url)

      if abs
        output = abs
      else
        @log.error("Error generating absolute urls: #{@url}, #{error}")
      end

      # Convert HTML to Markdown
      extensions = []

      if @format == :gfm
        extensions << '+yaml_metadata_block'
        extensions << '+definition_lists'
        extensions << '+footnotes'
      elsif @format == :markdown_mmd || @format == :markdown
        extensions << '+definition_lists'
        extensions << '+footnotes'
        extensions << '+table_captions'
        extensions << '+markdown_in_html_blocks'
        extensions << '+mmd_title_block'
        extensions << '+mmd_link_attributes'
        extensions << '+mmd_header_identifiers'
        extensions << '+superscript'
        extensions << '+subscript'
        extensions << '+backtick_code_blocks'
      end

      fmt = VALID_FORMATS.include?(@format.to_s) ? @format : :gfm

      output = Convert.new(output).format(fmt, extensions: extensions)

      # Clean up conversion output
      output = MarkdownCleaner.new(output).clean

      if output.length.positive?
        @log.info("Processed URL: #{@url}")
      else
        @log.error("Error processing URL: #{@url}")
        return false
      end

      @output = add_title(output.straighten_quotes)

      true
    end

    # Add source link and title to Markdown output
    def add_title(output)
      return output unless @params[:readability]

      if output =~ /^# (.*)$/
        output.sub!(/^# (.*)$/, '')
        title = Regexp.last_match[1]
      else
        title = @title
      end

      <<~RESULT
        [source](#{@url})

        # #{@title}

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
        puts '</head><body>'
        puts '<div id="wrapper">' if @params.key?(:style)
        out
        puts '</div>' if @params.key?(:style)
        puts '</body></html>'
      else
        out
      end
    end

    # Embed a style tag with compressed CSS
    def style
      return "" unless @params.key?(:style)

      css_style = @params[:style]
      return '' unless css_style

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
          ''
        end
      else
        ''
      end
    rescue StandardError => e
      @log.error("Error processing style: #{e.message}")
    end

    def import_css(url)
      content = Curl.new(url).fetch
      if content
        css = content[:source]
        css.absolute_urls!(url)
        "<style>#{css}</style>"
      else
        @log.error("Error importing CSS: #{url}")
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
        @cgi.out('application/json') { jsonify }
        return
      end

      # If output is to a link, generate the link and optionally open (with :open)
      if @link_type
        link = to_link.strip
        if @params[:open].to_s =~ /^1|t/ && @link_type != :url
          if link.length < 8000
            # puts @cgi.header('status' => 'REDIRECT', 'location' => link)
            buf = ' ' * 4096
            @cgi.out('status' => 'REDIRECT', 'connection' => 'close', 'location' => link) { buf }
            sleep 10
          else
            @cgi.out('text/html') { redirect(link) }
          end
        else
          @cgi.out('text/plain') { link }
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
        puts to_link
      else
        puts @output
      end
    end

    def redirect(url)
      <<~ENDHTML
        <html>
        <head>
          <meta http-equiv="refresh" content="0;url=#{url}" />
          <title></title>
        </head>
        <body></body>
        </html>
      ENDHTML
    end

    def to_link
      out_url = ERB::Util.url_encode(@output)
      title = ERB::Util.url_encode(@title.gsub(%r{/}, ':').strip)

      case @link_type
      when :url
        out_url
      when :obsidian
        "obsidian://new?name=#{title}&content=#{out_url}"
      when :nv
        "nv://make?title=#{title}&txt=#{out_url}"
      when :nvalt
        "nvalt://make?title=#{title}&txt=#{out_url}"
      when :nvultra
        "x-nvultra://make?title=#{title}&txt=#{out_url}"
      when :marked
        "x-marked://preview?text=#{out_url}"
      end
    end

    def jsonify
      output = { 'title' => @title, 'url' => @url, 'markup' => @output, 'html' => Convert.new(@output).html(@format) }
      output['link'] = to_link if @link_type
      output.to_json
    end

    def h3(content)
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

        value = if v.first == '1' || v.first == 'true'
                  true
                elsif v.first == '0' || v.first == 'false'
                  false
                else
                  v.first
                end
        @params[key] = value
      end
    end
  end
end

marky = Marky::Marky.new
marky.render
