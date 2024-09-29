# frozen_string_literal: true

require_relative "tty/which"
require "net/https"

class Curl
  def initialize(url)
    @curl = TTY::Which.which("curl")
    @url = url
  end

  def fetch(headers_only: false)
    @result = fetch_html(compressed: false, headers_only: headers_only)
  rescue StandardError => e
    puts e
  end

  def stylesheets
    return [] if @result.nil? || @result[:links].nil?

    @result[:links].select { |link| link[:rel] == "stylesheet" }.absolute_hrefs(@url)
  end

  def inline_styles
    return [] if @result.nil? || @result[:source].nil?

    @result[:source].scan(%r{<style.*?>(.*?)</style>}mi).flatten.join("\n")
  end

  def content
    @result[:source]
  end

  alias to_s content
  alias html content

  private

  class ::Array
    def absolute_hrefs(base_url)
      uri = URI(base_url)
      host = uri.host
      scheme = uri.scheme
      path = uri.path =~ %r{/$} ? uri.path : File.dirname(uri.path)
      base = "#{scheme}://#{host}#{path}"
      out = []

      each do |link|
        next if link[:href].nil?

        link[:href] = URI.join(base, link[:href]).to_s if link[:href] !~ %r{^(\w+:)?//}
        out << link[:href]
      end

      out
    rescue StandardError => e
      puts e
    end
  end

  ##
  ## Extract all meta tags from the document head
  ##
  ## @param      head [String] The head content
  ##
  ## @return     [Hash] hash of meta tags and values
  ##
  def meta_tags(head)
    meta = {}
    title = head.match(%r{(?<=<title>)(.*?)(?=</title>)})
    meta["title"] = title.nil? ? nil : title[1]
    refresh = head.match(/http-equiv=(['"])refresh\1(.*?)>/)
    url = refresh.nil? ? nil : refresh[2].match(/url=(.*?)['"]/)
    meta["refresh_url"] = url
    meta_tags = head.scan(/<meta.*?>/)
    meta_tags.each do |tag|
      meta_name = tag.match(/(?:name|property|http-equiv)=(["'])(.*?)\1/)
      next if meta_name.nil?

      meta_value = tag.match(/(?:content)=(['"])(.*?)\1/)
      next if meta_value.nil?

      meta[meta_name[2].downcase] = meta_value[2]
    end
    meta
  rescue StandardError => e
    warn e
    {}
  end

  ##
  ## Extract all <link> tags from head
  ##
  ## @param      head  [String] The head content
  ##
  ## @return     [Array] Array of links
  ##
  def link_tags(head)
    links = []
    link_tags = head.scan(/<link.*?>/)
    link_tags.each do |tag|
      link_rel = tag.match(/rel=(['"])(.*?)\1/)
      link_rel = link_rel.nil? ? nil : link_rel[2]

      next if link_rel =~ /preload/

      link_href = tag.match(/href=(["'])(.*?)\1/)
      next if link_href.nil?

      link_href = link_href[2]

      if @local_links_only
        next if @ignore_fragment_links && link_href =~ /^#/

        next unless same_origin?(link_href)
      else
        next if link_href =~ /^#/ && (@ignore_fragment_links || @external_links_only)

        next if link_href !~ %r{^(\w+:)?//} && (@ignore_local_links || @external_links_only)

        next if same_origin?(link_href) && @external_links_only
      end

      link_title = tag.match(/title=(['"])(.*?)\1/)
      link_title = link_title.nil? ? nil : link_title[2]

      link_type = tag.match(/type=(['"])(.*?)\1/)
      link_type = link_type.nil? ? nil : link_type[2]

      links << { rel: link_rel, href: link_href, type: link_type, title: link_title }
    end
    links
  end

  ##
  ## Get the source of a web page using Ruby with a fallback to curl
  ## Try multiple agents if the page is not fetched
  ##
  ## @param      url           [String] The url
  ## @param      headers       [Hash] The headers
  ## @param      headers_only  [Boolean] Return headers only
  ## @param      compressed    [Boolean] expect compressed results
  ##
  ## @return     [Hash] hash of url, code, meta, links, head, body, source
  ##
  def fetch_html(url = nil, headers: nil, headers_only: false, compressed: false)
    url ||= @url
    raise StandardError, "Missing URL" if url.nil? || !url

    redirects = 0

    begin
      break if redirects > 2

      redirects += 1
      response = Net::HTTP.get_response(URI.parse(url))

      break if response["location"].nil?

      break if response["location"] == url

      Marky.log.debug "Following redirect to #{response["location"]}"

      url = response["location"]
    end while response.is_a?(Net::HTTPRedirection)

    agents = [
      "Marky/1.0 (en-US; rv:1.0.1) bot",
      "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Safari/605.1.1",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:121.0) Gecko/20100101 Firefox/121.",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/109.0.0.0 Safari/537.3",
      "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36 Edg/120.0.0.",
    ]
    agent = 0
    res = nil
    while res.nil? || res[:body].nil? || res[:body].empty? || res[:body] =~ /enable javascript.*?continue/i || res[:body] =~ /403 forbidden/i
      break if agent > agents.count - 1

      res = ruby_html(url, headers: headers, compressed: compressed, agent: agents[agent])
      agent += 1
    end

    if res.nil? || res[:source].nil? || res[:source].empty?
      agent = 0
      while res.nil? || res[:body].nil? || res[:body].empty? || res[:body] =~ /enable javascript.*?continue/i || res[:body] =~ /403 forbidden/i
        break if agent > agents.count - 1

        res = curl_html(url, headers: headers, headers_only: headers_only, compressed: compressed, agent: agents[agent])
        agent += 1
      end
    end

    return false if res.nil? || res[:source].nil? || res[:source].empty?

    @source = res[:source]

    @source.strip!

    head = @source.match(%r{(?:<head[^>]*>)(.*?)(?=</head>)}mi)

    if head.nil?
      { url: url, code: res[:code], meta: nil, links: nil, head: nil, body: @source.strip,
        source: @source.strip }
    else
      @body = @source.match(%r{<body.*?>(.*?)</body>}mi)[1]
      meta = meta_tags(head[1])
      links = link_tags(head[1])

      { url: url, code: res[:code], meta: meta, links: links, head: head[1], body: @body,
        source: @source.strip }
    end
  end

  (Net::HTTP::SSL_IVNAMES << :@ssl_options).uniq!
  (Net::HTTP::SSL_ATTRIBUTES << :options).uniq!

  Net::HTTP.class_eval do
    attr_accessor :ssl_options
  end

  ##
  ## Get contents of web page using net/http/
  ##
  ## @param      url           [String] The url
  ## @param      headers       [Hash] The headers
  ## @param      compressed    [Boolean] expect compressed results
  ## @param      agent         [String] The user agent
  ##
  ## @return     [Hash] response code, contents of the page
  def ruby_html(url = nil, headers: nil, compressed: false, agent: nil)
    url ||= @url

    raise StandardError, "Missing URL" if url.nil? || !url

    uri = URI.parse(url)

    http = Net::HTTP.new(uri.host, uri.port)

    options_mask = OpenSSL::SSL::OP_NO_SSLv2 + OpenSSL::SSL::OP_NO_SSLv3 +
                   OpenSSL::SSL::OP_NO_COMPRESSION

    if uri.scheme == "https"
      http.use_ssl = true
      http.verify_mode = OpenSSL::SSL::VERIFY_PEER
      http.ssl_options = options_mask
      http.ca_file = "/etc/ssl/certs/ca-certificates.crt"
    end

    req = Net::HTTP::Get.new(uri, { "User-Agent" => agent })
    req["Accept-Encoding"] = "gzip" if compressed
    req["Access-Control-Allow-Origin"] = "*"
    req["Access-Control-Allow-Methods"] = "POST, PUT, DELETE, GET, OPTIONS"
    req["Access-Control-Request-Method"] = "*"
    req["Access-Control-Allow-Headers"] = "Origin, X-Requested-With, Content-Type, Accept, Authorization"
    headers.each { |k, v| req[k] = v } unless headers.nil?

    res = http.request(req)

    { code: res.code, source: reencode(res.body) }
  end

  ##
  ## Curls the html for the page
  ##
  ## @param      url           [String] The url
  ## @param      headers       [Hash] The headers
  ## @param      headers_only  [Boolean] Return headers only
  ## @param      compressed    [Boolean] expect compressed results
  ## @param      agent         [String] The user agent
  ##
  ## @return     [Hash] hash of code, source
  ##
  def curl_html(url = nil, headers: nil, headers_only: false, compressed: false, agent: nil)
    url ||= @url
    raise StandardError, "Missing URL" if url.nil? || !url

    flags = "SsL"
    flags += headers_only ? "I" : "i"

    headers = headers.nil? ? "" : headers.map { |h, v| %(-H "#{h}: #{v}") }.join(" ")
    compress = @compressed ? "--compressed" : ""
    # source = `#{@curl} -#{flags} #{compress} #{headers} '#{url}' 2>/dev/null`
    source = nil
    cmd = %(#{@curl} -#{flags} #{compress} -A "#{agent}" #{headers} "#{url}" 2>/dev/null)
    source = `#{cmd}`

    return false unless $?.success?

    headers = { "location" => url }
    lines = source.split(/\r\n/)
    code = lines[0].match(/(\d\d\d)/)[1]
    lines.shift
    lines.each_with_index do |line, idx|
      if line =~ /^([\w-]+): (.*?)$/
        m = Regexp.last_match
        headers[m[1]] = m[2]
      else
        source = lines[idx..].join("\n")
        break
      end
    end

    # if headers['content-encoding'] =~ /gzip/i && !compressed
    #   @source = curl_html(url, headers: headers,
    #                            compressed: true)
    # end

    { code: code, source: reencode(source) }
  end

  ##
  ## Reencode the content (borrowed from Nokogiri)
  ##
  ## @param      body          [String] The body
  ## @param      content_type  [String] Force content type
  ##
  def reencode(body, content_type = nil)
    if body.encoding == Encoding::ASCII_8BIT
      encoding = nil

      # look for a Byte Order Mark (BOM)
      initial_bytes = body[0..2].bytes
      if initial_bytes[0..2] == [0xEF, 0xBB, 0xBF]
        encoding = Encoding::UTF_8
      elsif initial_bytes[0..1] == [0xFE, 0xFF]
        encoding = Encoding::UTF_16BE
      elsif initial_bytes[0..1] == [0xFF, 0xFE]
        encoding = Encoding::UTF_16LE
      end

      # look for a charset in a content-encoding header
      encoding ||= content_type[/charset=["']?(.*?)($|["';\s])/i, 1] if content_type

      # look for a charset in a meta tag in the first 1024 bytes
      unless encoding
        data = body[0..1023].gsub(/<!--.*?(-->|\Z)/m, "")
        data.scan(/<meta.*?>/im).each do |meta|
          encoding ||= meta[/charset=["']?([^>]*?)($|["'\s>])/im, 1]
        end
      end

      # if all else fails, default to the official default encoding for HTML
      encoding ||= Encoding::ISO_8859_1

      # change the encoding to match the detected or inferred encoding
      body = body.dup
      begin
        body.force_encoding(encoding)
      rescue ArgumentError
        body.force_encoding(Encoding::ISO_8859_1)
      end
    end

    body.encode(Encoding::UTF_8)
  end

  ##
  ## Test if a given url has the same hostname as @url
  ##
  ## @param      href  [String] The url to test
  ##
  ## @return     [Boolean] true if hostnames match
  ##
  def same_origin?(href)
    uri = URI(href)
    origin = URI(@url)
    uri.host == origin.host
  rescue StandardError
    false
  end
end
