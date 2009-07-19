require File.join(File.dirname(__FILE__), 'helper')

class TestCurbCurlMulti < Test::Unit::TestCase
  def teardown
    # get a better read on memory loss when running in valgrind
    ObjectSpace.garbage_collect
  end

  def test_new_multi_01
    d1 = ""
    c1 = Curl::Easy.new($TEST_URL) do |curl|
      curl.headers["User-Agent"] = "myapp-0.0"
      curl.on_body {|d| d1 << d; d.length }
    end

    d2 = ""
    c2 = Curl::Easy.new($TEST_URL) do |curl|
      curl.headers["User-Agent"] = "myapp-0.0"
      curl.on_body {|d| d2 << d; d.length }
    end

    m = Curl::Multi.new

    m.add( c1 )
    m.add( c2 )

    m.perform
    
    assert_match(/^# DO NOT REMOVE THIS COMMENT/, d1)
    assert_match(/^# DO NOT REMOVE THIS COMMENT/, d2)

    m = nil

  end

  def test_perform_block
    c1 = Curl::Easy.new($TEST_URL)
    c2 = Curl::Easy.new($TEST_URL)

    m = Curl::Multi.new

    m.add( c1 )
    m.add( c2 )

    m.perform do
      # idle
      puts "idling..."
    end

    assert_match(/^# DO NOT REMOVE THIS COMMENT/, c1.body_str)
    assert_match(/^# DO NOT REMOVE THIS COMMENT/, c2.body_str)
    
    m = nil

  end

  def test_n_requests
    n = 100
    running = true
    queue = Queue.new
    # have a thread running in the background
    thread = Thread.new { queue.pop }
    m = Curl::Multi.new
    assert_equal Curl::Multi, m.class
    responses = []
    n.times do|i|
      responses[i] = ""
      c = Curl::Easy.new($TEST_URL) do|curl|
        curl.on_body{|data| responses[i] << data; data.size }
      end
      m.add c
    end

    m.perform

    assert n, responses.size
    n.times do|i|
      assert_match(/^# DO NOT REMOVE THIS COMMENT/, responses[i], "response #{i}")
    end
    queue.push 1
    m = nil
  end

  def test_n_requests_with_break
    # process n requests then load the handle again and run it again
    n = 2
    m = Curl::Multi.new
    5.times do|it|
      responses = []
      n.times do|i|
        responses[i] = ""
        c = Curl::Easy.new($TEST_URL) do|curl|
          curl.on_body{|data| responses[i] << data; data.size }
        end
        m.add c
      end
      m.perform

      assert n, responses.size
      n.times do|i|
        assert_match(/^# DO NOT REMOVE THIS COMMENT/, responses[i], "response #{i}")
      end
    end
    
    m = nil

  end
  
  def test_idle_check
    m = Curl::Multi.new
    e = Curl::Easy.new($TEST_URL)
    
    assert(m.idle?, 'A new Curl::Multi handle should be idle')
    
    m.add(e)
    
    assert((not m.idle?), 'A Curl::Multi handle with a request should not be idle')
    
    m.perform
    
    assert(m.idle?, 'A Curl::Multi handle should be idle after performing its requests')
  end
  
  def test_requests
    m = Curl::Multi.new
    
    assert_equal([], m.requests, 'A new Curl::Multi handle should have no requests')
    
    10.times do
      m.add(Curl::Easy.new($TEST_URL))
    end
    
    assert_equal(10, m.requests.length, 'multi.requests should contain all the active requests')
    
    m.perform
    
    assert_equal([], m.requests, 'A new Curl::Multi handle should have no requests after a perform')
  end
  
  def test_cancel
    m = Curl::Multi.new
    m.cancel! # shouldn't raise anything
    
    10.times do
      m.add(Curl::Easy.new($TEST_URL))
    end
    
    m.cancel!
    
    assert_equal([], m.requests, 'A new Curl::Multi handle should have no requests after being canceled')
  end

  def test_with_success
    c1 = Curl::Easy.new($TEST_URL)
    c2 = Curl::Easy.new($TEST_URL)
    success_called1 = false
    success_called2 = false
 
    c1.on_success do|c|
      success_called1 = true
      assert_match(/^# DO NOT REMOVE THIS COMMENT/, c.body_str)
    end

    c2.on_success do|c|
      success_called2 = true
      assert_match(/^# DO NOT REMOVE THIS COMMENT/, c.body_str)
    end

    m = Curl::Multi.new

    m.add( c1 )
    m.add( c2 )

    m.perform do
      # idle
      puts "idling..."
    end

    assert success_called2
    assert success_called1
 
    m = nil
  end
  
  def test_with_success_cb_with_404
    c1 = Curl::Easy.new("#{$TEST_URL.gsub(/file:\/\//,'')}/not_here")
    c2 = Curl::Easy.new($TEST_URL)
    success_called1 = false
    success_called2 = false
    
    c1.on_success do|c|
      success_called1 = true
      #puts "success 1 called: #{c.body_str.inspect}"
      #assert_match(/^# DO NOT REMOVE THIS COMMENT/, c.body_str)
    end

    c1.on_failure do|c,rc|
      # rc => [Curl::Err::MalformedURLError, "URL using bad/illegal format or missing URL"]
      assert_equal Curl::Easy, c.class
      assert_equal Curl::Err::MalformedURLError, rc.first
      assert_equal "URL using bad/illegal format or missing URL", rc.last
    end

    c2.on_success do|c|
    #  puts "success 2 called: #{c.body_str.inspect}"
      success_called2 = true
      assert_match(/^# DO NOT REMOVE THIS COMMENT/, c.body_str)
    end

    m = Curl::Multi.new

    #puts "c1: #{c1.url}"
    m.add( c1 )
    #puts "c2: #{c2.url}"
    m.add( c2 )

    #puts "calling"
    m.perform do
      # idle
    end

    assert success_called2
    assert !success_called1
 
    m = nil
  end

  class TestForScope
    attr_reader :buf

    def t_method
      @buf = ""
      @m = Curl::Multi.new
      10.times do|i|
        c = Curl::Easy.new($TEST_URL)
        c.on_success{|b| @buf << b.body_str }
        ObjectSpace.garbage_collect
        @m.add(c)
        ObjectSpace.garbage_collect
      end
      ObjectSpace.garbage_collect
    end

    def t_call
      @m.perform do
        ObjectSpace.garbage_collect
      end
    end

    def self.test
      ObjectSpace.garbage_collect
      tfs = TestForScope.new
      ObjectSpace.garbage_collect
      tfs.t_method
      ObjectSpace.garbage_collect
      tfs.t_call
      ObjectSpace.garbage_collect

      tfs.buf
    end

  end

  def test_with_garbage_collect
    ObjectSpace.garbage_collect
    buf = TestForScope.test
    ObjectSpace.garbage_collect
    assert_match(/^# DO NOT REMOVE THIS COMMENT/, buf)
  end

=begin
  def test_remote_requests
    responses = {}
    requests = ["http://google.co.uk/", "http://ruby-lang.org/"]
    m = Curl::Multi.new
    # add a few easy handles
    requests.each do |url|
      responses[url] = ""
      responses["#{url}-header"] = ""
      c = Curl::Easy.new(url) do|curl|
        curl.follow_location = true
        curl.on_header{|data| responses["#{url}-header"] << data; data.size }
        curl.on_body{|data| responses[url] << data; data.size }
        curl.on_success {
          puts curl.last_effective_url 
        }
      end
      m.add(c)
    end

    m.perform

    requests.each do|url|
      puts responses["#{url}-header"].split("\r\n").inspect
      #puts responses[url].size
    end
  end
=end

  def test_multi_easy_get_01
    urls = []
    root_uri = 'http://127.0.0.1:9129/ext/'
    # send a request to fetch all c files in the ext dir
    Dir[File.dirname(__FILE__) + "/../ext/*.c"].each do|path|
      urls << root_uri + File.basename(path)
    end
    Curl::Multi.get(urls, {:follow_location => true}, {:pipeline => true}) do|curl|
      assert_equal 200, curl.response_code
    end
  end

  def test_multi_easy_post_01
    urls = [
      { :url => TestServlet.url + '?q=1', :post_fields => {'field1' => 'value1', 'k' => 'j'}},
      { :url => TestServlet.url + '?q=2', :post_fields => {'field2' => 'value2', 'foo' => 'bar', 'i' => 'j' }},
      { :url => TestServlet.url + '?q=3', :post_fields => {'field3' => 'value3', 'field4' => 'value4'}}
    ]
    Curl::Multi.post(urls, {:follow_location => true, :multipart_form_post => true}, {:pipeline => true}) do|easy|
      str = easy.body_str
      assert_match /POST/, str
      fields = {}
      str.gsub(/POST\n/,'').split('&').map{|sv| k, v = sv.split('='); fields[k] = v }
      expected = urls.find{|s| s[:url] == easy.last_effective_url }
      assert_equal expected[:post_fields], fields
      #puts "#{easy.last_effective_url} #{fields.inspect}"
    end
  end

  include TestServerMethods 

  def setup
    server_setup
  end

end
