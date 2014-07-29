#!/usr/bin/env ruby
# encoding: utf-8
require 'net/http'
require 'uri.rb'
ENV['TZ'] = "Asia/Shanghai"
# 线程池
class ThreadPool
  class Worker
    def initialize
      @mutex = Mutex.new
      @thread = Thread.new do
        while true
          sleep 0.001
          block = get_block
          if block
            block.call
            reset_block
          end
        end
      end
    end
    
    def get_block
      @mutex.synchronize {@block}
    end
    
    def set_block(block)
      @mutex.synchronize do
        raise RuntimeError, "Thread already busy." if @block
        @block = block
      end
    end
    
    def reset_block
      @mutex.synchronize {@block = nil}
    end
    
    def busy?
      @mutex.synchronize {!@block.nil?}
    end
  end
  
  attr_accessor :max_size
  attr_reader :workers

  def initialize(max_size = 10)
    @max_size = max_size
    @workers = []
    @mutex = Mutex.new
  end
  
  def size
    @mutex.synchronize {@workers.size}
  end
  
  def busy?
    @mutex.synchronize {@workers.any? {|w| w.busy?}}
  end
  
  def join
    sleep 0.01 while busy?
  end
  
  def process(&block)
    wait_for_worker.set_block(block)
  end
  
  def wait_for_worker
    while true
      worker = find_available_worker
      return worker if worker
      sleep 0.01
    end
  end
  
  def find_available_worker
    @mutex.synchronize {free_worker || create_worker}
  end
  
  def free_worker
    @workers.each {|w| return w unless w.busy?}; nil
  end
  
  def create_worker
    return nil if @workers.size >= @max_size
    worker = Worker.new
    @workers << worker
    worker
  end
end
$pool = ThreadPool.new(6)
class KTXP_Item
    attr_accessor :time,:type,:torrent,:url,:title,:size,:name,:slice,:group
    def nil?
        [@time,@type,@torrent,@url,@title,@size,@slice].any?{|i|i==nil}
    end
end
$animeCollet = []
module GAL # 咳…绝对是Get Anime List……
    def self.get(url)
        uri = URI.parse(URI.encode(url))
        req = Net::HTTP::Get.new(url)
        req.add_field('User-Agent', 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Ubuntu Chromium/28.0.1500.71 Chrome/28.0.1500.71 Safari/537.36')
        res = Net::HTTP.start(uri.host, uri.port) {|http| http.request(req) }
        return res.body.force_encoding("utf-8")
    end
    def self.ktxp(keyword, name, slice, group)
        t = Time.now
          search_page = self.get("http://bt.ktxp.com/search.php?keyword=#{URI.encode(keyword)}")
          total = search_page[/<h2><a href="\/search\.php\?keyword=.*?\((\d+?)\)<\/a>/] ? $1.to_i : 0
          return if total == 0
          $animeCollet.push(*parse(search_page, name, slice, group))
          # 分页
          if total > 100
            tp = (total / 100.0).ceil - 1
            tp.times.each{|i|
                $pool.process{
                    tt = Time.now
                    search_page = self.get("http://bt.ktxp.com/search.php?keyword=#{URI.encode(keyword)}&page=#{i+2}")
                    $animeCollet.push(*parse(search_page, name, slice, group))
                    p "#{i}:#{Time.now-tt}"
                }
            }
          end
    end
    def self.parse(page, name, slice, group)
        result = []
          page.scan(/<tr>.*?<\/tr>/m){|item|
            ki = KTXP_Item.new
            ki.time = item[/<td title=\"(.*?)\">/] ? $1 : nil
            next unless ki.time
            ki.time = Time.mktime(*ki.time.gsub!(/\/|\-|:/, " ").split(" "))
            item[/<a href="([^"]*?)" target="_blank">(.*?)<\/a>/]
            ki.url = "http://bt.ktxp.com" + $1
            ki.title = $2.gsub('<span class="keyword">', "").gsub("</span>", "").gsub("&amp;","&")
            item[/<a href="([^"]*?)" class="quick-down cmbg"><\/a>/]
            ki.torrent = "http://bt.ktxp.com" + $1
            item[/<td><a href="[^"]*?">([^"]*?)<\/a>/]
            ki.type = $1
            item[/<td>([0-9.BKMGT]*?)<\/td>/]
            ki.size = $1
            ki.name = name
            ki.title[slice]
            ki.slice = $1
            ki.group = group
            next if ki.nil?
            result.push(ki)
          }
          return result
    end
end

def makeItem(anime, cover, download, size, date, other)
result= <<EOF
                <div class="anime-item">
                    <div class="anime">#{anime}</div>
                    <img class="cover" src="assets/image/onair-#{cover}.png"/>
                    <a href="#{download}">
                        <div class="download">下载 (#{size})</div>
                    </a>
                    <div class="date">#{date}</div>
                    <div>#{other}</div>
                </div>
EOF
    return result
end
def makePage(animeItem, time, makeTime, update)
page = <<EOF
<!DOCTYPE html>
<html>
    <head>
        <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>onAir</title>
        <link rel="stylesheet" type="text/css" href="assets/style/normalize.css" media="screen" />
        <link rel="stylesheet" type="text/css" href="assets/style/main.css" media="screen" />
    </head>
    <body>
        <div class="context">
            <div class="title">
                    <span class="title-text">onAir</span>
            </div>
            <div class="anime-list">
                #{animeItem}
            </div>
            <div class="publish-time">GTM+8,#{time}</br>Processed in #{makeTime}second(s),#{update} updated</div>
        </div>
    </body>
</html>
EOF
    return page
end
# IMAGE_TABLE = {
#     "No Game No Life" => "06",
#     "一周的朋友" => "05",
#     "LoveLive!2nd" => "04",
#     "请问您今天要来点兔子吗？" => "03",
#     "魔法科高校的劣等生" => "02",
#     "目隐都市的演绎者" => "01"
# }
# ANIME_LIST = [
#     ["No Game No Life 澄空 MP4 720p", "No Game No Life", /第(\d+)话/, "澄空学园"],
#     ["一周的朋友 澄空 MP4 720p", "一周的朋友", /第(\d+)话/, "澄空学园"],
#     ["LoveLive!2nd 澄空 MP4 720p", "LoveLive!2nd", /第(\d+)话/, "澄空x华盟"],
#     ["请问您今天要来点兔子吗 澄空 MP4 720p", "请问您今天要来点兔子吗？", /第(\d+)话/, "澄空x华盟"],
#     ["魔法科高中的劣等生 澄空 GB MP4 720p", "魔法科高校的劣等生", /\[(\d+)\]/, "澄空x华盟"],
#     ["目隐都市的演绎者 澄空 简体 MP4 720p", "目隐都市的演绎者", /第(\d+)话/, "澄空x华盟"]
# ]

IMAGE_TABLE = {
    "魔法科高校的劣等生" => "01",
    "刀剑神域Ⅱ幽灵子弹" => "02",
    "三坪房间的侵略者" => "03",
    "RAIL WARS!" => "04",
    "Free! -Eternal Summer-" => "05",
    "花舞少女" => "06",
    "精灵使的剑舞" => "07",
    "搞姬日常" => "08",
    "人生" => "09"
}

ANIME_LIST = [
  ["魔法科高中的劣等生 澄空 GB MP4 720p", "魔法科高校的劣等生", /\[(\d+)\]/, "澄空x华盟"],
  ["澄空 华盟 刀剑神域Ⅱ 简 720p MP4", "刀剑神域Ⅱ幽灵子弹", /第(\d+)话/, "澄空x华盟"],
  ["澄空 华盟 三坪房间的侵略者 MP4 720p", "三坪房间的侵略者", /第(\d+)话/, "澄空x华盟"],
  ["澄空 华盟 RAIL WARS! 简体720p MP4", "RAIL WARS!", /第(\d+)话/, "澄空x华盟"],
  ["极影 Free! Eternal Summer GB_CN 720p MP4", "Free! -Eternal Summer-", /第(\d+)话/, "极影字幕社"],
  ["澄空 华盟 TFO 花舞少女 MP4 720p", "花舞少女", /第(\d+)话/, "澄空x华盟xTFO"],
  ["极影 精灵使的剑舞 GB 720P MP4", "精灵使的剑舞", /第(\d+)话/, "极影字幕社"],
  ["澄空 搞姬日常 MP4 720p", "搞姬日常", /第(\d+)话/, "澄空学园"],
  ["极影 人生 GB_CN 720p MP4", "人生", /第(\d+)集/, "极影字幕社"]
]

timer = Time.now
$animeCollet = []
ANIME_LIST.each {|a|GAL.ktxp(*a)}
$animeCollet.sort!{|a,b|b.time<=>a.time}
pageTemp = ""
$animeCollet.each{|item|
    pageTemp += makeItem(item.name, IMAGE_TABLE[item.name], item.torrent, item.size, item.time.strftime("%Y-%m-%d %H:%M"), "第" + item.slice + "话, " + item.group)
}
open("/var/www/lynn/onair/index.html", "w+"){|io|io.write(makePage(pageTemp,Time.now.strftime("%Y-%m-%d %H:%M"),Time.now-timer,$animeCollet.size))}