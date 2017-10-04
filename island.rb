#!/usr/bin/env ruby
require 'rubygems'
require 'gosu'
require 'chipmunk'
require 'yaml'
require 'dentaku'
include CP

class IslandWindow < Gosu::Window

  G = 1000

  def v a, b
    Vec2.new a, b
  end

  def v_limits w, h
    [[0, 0], [0, h], [w, h], [w, 0]].map { |x| v(*x) }
  end

  def initialize_sensor_shape e, kind
    exit_shape = Shape::Poly.new Body.new(INFINITY, INFINITY), v_limits(*e[2..3]), v(*e[0..1])
    exit_shape.collision_type = kind
    exit_shape.sensor = true
    @space.add_static_shape exit_shape
    exit_shape
  end

  def initialize_exit
    @exit = @scene["exit"]
    @exit_shape = initialize_sensor_shape @exit, :exit
  end

  def initialize_letters
    letters = @scene["letters"] || []
    @letters = Hash[letters.map do |name, position|
      shape = initialize_sensor_shape(position, :letter)
      shape.object = name
      [name, {shape: shape}]
    end]
  end

  def remove_shape_and_body shape, static = true
    if static
      @space.remove_static_shape shape
    else
      @space.remove_shape shape
    end
    @space.remove_body shape.body
  end

  def delete_scene
    remove_shape_and_body @exit_shape
    @platforms.each { |platform| remove_shape_and_body platform }
    @blocks.each { |k, conf| remove_shape_and_body conf[:shape], false }
    @letters.each { |k, conf| remove_shape_and_body conf[:shape] }
    @decorations = []
    @timeout_actions = []
  end

  def load_scene
    delete_scene
    next_scene
    initialize_scene
  end

  def letter_collision_callback letter_shape
      name = letter_shape.object
      letter = @letters[name] || {}
      if not letter[:read]
        letter[:read] = true
        @letter_name = name
      end
  end

  def exit_collision_callback
      @space.add_post_step_callback(1) do 
        @level_i += 1
        load_scene
      end if @up
  end

  def initialize_collisions_callbacks
    {
      [:ground, :block] => ->(b) { @touching_ground = true },
      [:exit] => ->(e) { exit_collision_callback },
      [:letter] => ->(l) { letter_collision_callback(l) },
    }.map { |k, v| k.each { |j| @space.add_collision_func(:character, j) { |c, o| v.call(o) }  } }
  end


  def initialize_physics
    @space = Space.new
    @space.damping = 0.8
    @space.gravity = v(0, G)
    character_body = Body.new 10, INFINITY  # infinite moment of inertia makes body non rotatable
    w = @character_noframes.width * 0.25
    h = @character_noframes.height * 0.25
    @character_shape = Shape::Poly.new character_body, v_limits(w, h), v(0, 0)
    @character_shape.collision_type = :character
    @character_shape.u = 1.5
    @character_shape.body.v_limit = 500
    @space.add_body character_body
    @space.add_shape @character_shape
    initialize_collisions_callbacks
  end

  def segment_shape conf, body
    pos = conf["pos"]
    body.pos = v(*pos[0..1])
    Shape::Segment.new body, v(0, 0), v(pos[2] - pos[0], pos[3] - pos[1]), 3
  end

  def initialize_segment collision_type, conf, body = Body.new(INFINITY, INFINITY)
    shape = segment_shape conf, body
    shape.collision_type = collision_type
    shape.u = 1.7
    shape.e = 0
    yield shape
    shape
  end

  def image_scale image, size
    [size[0].to_f / image.width, size[1].to_f / image.height]
  end

  def draw_exit
    @white_circle.draw @exit_shape.body.p.x, @exit_shape.body.p.y
  end

  def initialize_segments collision_type, configuration
    configuration.map do |k, conf| 
      initialize_segment(collision_type, conf) do |s|
        @space.add_static_shape s
      end
    end
  end

  def initialize_platforms
    @platforms = {ground: @scene["platforms"], wall: @scene["walls"]}.map do |k, conf|
      initialize_segments k, conf
    end.flatten
  end

  def merge_image name, conf
    image = Gosu::Image.new("media/#{name.sub(/-.*/, "")}.png")
    size = conf["size"] || [image.width, image.height]
    scale = image_scale image, size
    {scale: scale, image: image}.merge(conf)
  end

  def initialize_block conf
    size = conf["size"]
    shape = Shape::Poly.new(Body.new(100, INFINITY),
                            v_limits(*size[0..1]), v(*conf["pos"]))
    shape.collision_type = :block
    shape.u = 1.7
    @space.add_body shape.body
    @space.add_shape shape
    shape
  end


  def initialize_blocks
    @blocks = (@scene["blocks"] || []).map do |name, conf|
      [name, {shape: initialize_block(conf)}.merge(merge_image(name, conf))]
    end
  end

  def initialize_decorations
    @decorations = @scene["decorations"].map do |k, conf|
      conf = {"pos"=>[0, 0]}.merge(conf.nil? ? {} : conf) if conf.nil? or conf["pos"].nil?
      [k, merge_image(k, conf)]
    end
  end

  def initialize_scene
    initialize_platforms
    initialize_blocks
    @character_shape.body.p = v(*@scene["entry"])
    initialize_exit
    initialize_letters
    initialize_decorations
  end

  def next_scene
    @@scenes_path = 'scenes.yml'
    @level = YAML.load_file(@@scenes_path)["beach"]
    @last_scenes_mtime = File.mtime @@scenes_path
    @music ||= Gosu::Sample.new "media/#{@level["music"]}.ogg"
    @level_i ||= (ARGV[0] || 0).to_i
    scenes = @level["scenes"]
    @scene = scenes[scenes.keys[@level_i]]
    @letter = @letter_image = @letter_text = nil
    @crystal_enabled = false
    @crystal_discharged = false
  end

  def initialize
    next_scene
    super( 2400, 1600, false )
    @calculator = Dentaku::Calculator.new
    @character_frames = Dir.glob('media/character/*.png').map { |x| Gosu::Image.new(x) }
    @character_noframes = Gosu::Image.new('media/character.png')
    @circle = Gosu::Image.new('media/white_circle.png')
    @sheet = Gosu::Image.new('media/sheet.png')
    initialize_physics
    initialize_scene
    @t = 0
    @translation = 0
    @direction = 1
  end

  def ground_y pos
    @scene["platforms"].each do |k, v|
      platform = v["pos"]
      if platform[0] < pos[0] and pos[0] < platform[2]
        return platform[1]
      end
    end
    0
  end

  def shadow_y pos, image, scale
    ground = ground_y pos
    delta = ground - image.height * scale[1] - pos[1]
    ground - image.height * scale[1] + delta
  end

  def draw_shadow scale, image, pos, direction = 1, from_ground = true
    y = from_ground ? shadow_y(pos, image, scale) : pos[1]
    image.draw_rot(pos[0], y, 0, 180, 0, 2, -1.0 * scale[0] * direction, scale[1], 0x11_000000)
  end

  def draw_crystal_power x, y, scale
    size = 3 * scale + (0.2 * scale * Math::sin(@t / 20))
    @circle.draw(x, @character_shape.body.p.y, 0, size * @direction, size, 0x22_ff0000)
  end

  def draw_character
    if @translation == 0
      @character = @character_noframes
    elsif @touching_ground
      if @translation < 0
        @character_shape.body.apply_impulse(v(-500.0, 0.0), v(0.0, 0.0))
        @direction = -1 
      elsif @translation > 0
        @character_shape.body.apply_impulse(v(500.0, 0.0), v(0.0, 0.0))
        @direction = 1 
      end
      @character = @character_frames[Gosu.milliseconds / 100 % @character_frames.size]
    end
    x = @character_shape.bb.l
    x += @character_shape.bb.r - @character_shape.bb.l if @direction == -1
    scale = 0.25
    draw_crystal_power x, @character_shape.body.p.y, scale if @crystal_enabled
    @character.draw(x, @character_shape.body.p.y, 0, scale * @direction, scale)
    draw_shadow [scale, scale], @character, [x, @character_shape.body.p.y], @direction
  end

  def draw_bounding_box shape, color = Gosu::Color::RED,
    a = shape.bb
    points = [[a.l, a.t], [a.r, a.t], [a.r, a.b], [a.l, a.b]]
    points.each_with_index do |point, i|
      n = (i + 1) % points.size
      draw_line *point[0..1], color, *points[n][0..1], color
    end
  end

  def draw_blocks
    @blocks.each do |k, conf|
      conf[:image].draw conf[:shape].bb.l, conf[:shape].bb.b, 0, *conf[:scale][0..1]
      draw_shadow conf[:scale], conf[:image], [conf[:shape].bb.l, conf[:shape].bb.b]
    end
  end

  def draw_decorations
    @calculator.store(t: @t.to_f)
    @decorations.each do |k, conf|
      pos = conf["pos"].map { |x| x.class == Integer ? x : @calculator.evaluate(x).to_f }
      color = conf["color"]
      scale = conf["scale"].nil? ? [1, 1] : conf["scale"]
      z = conf["z"].nil? ? 0 : conf["z"]
      if conf["angle"].nil?
        conf[:image].draw(*pos[0..1], z, scale[0], scale[1], color.nil? ? 0xff_ffffff : color)
      else
        conf[:image].draw_rot(*pos[0..1], z, conf["angle"], 0, 0, *scale[0..1], color.nil? ? 0xff_ffffff : color)
      end
      draw_shadow scale, conf[:image], pos, 1, false if not conf["shadow"].nil?
    end
  end

  def draw_letter
    @sheet.draw 500, 50, 0, 0.6, 0.6
    @letter ||= YAML.load_file('letters.yaml')["beach"]
    image = @letter["image"]
    @letter_image ||= Gosu::Image.new("media/#{image["name"]}.png")
    @letter_text ||= Gosu::Image.from_text(
        self, @letter["text"], "media/HelloPicasso.ttf", 70)
    @letter_text.draw 650, 100, 0, 1, 1, 0xff_000000
    pos = image["pos"]
    scale = image["scale"]
    @letter_image.draw *pos[0..1], 0, scale, scale
  end

  def configuration_updated
    current_scenes_mtime = File.mtime @@scenes_path
    res = @last_scenes_mtime < current_scenes_mtime
    @last_scenes_mtime = current_scenes_mtime
    res
  end

  def draw
    run_timeout_actions
    @touching_ground = false
    @space.step((1.0/60.0))
    @t += 1
    draw_decorations
    draw_exit
    draw_character
    draw_blocks
    if @bounding_boxes
      draw_bounding_box @character_shape
      draw_bounding_box @exit_shape
      @platforms.each { |platform| draw_bounding_box platform }
      @letters.each { |k, letter| draw_bounding_box letter[:shape] }
      @blocks.each { |k, block| draw_bounding_box block[:shape] }
    end
    draw_letter if @letter_name
    load_scene if @t % 50 == 0 and configuration_updated
  end

  def compensate_mass shape
    shape.body.apply_force v(0, - 1.00001 * shape.body.m * G), v(0, 0)
    shape.body.p.y -= 1
  end

  def run_timeout_actions
    to_remove = []
    now = Gosu.milliseconds
    (@timeout_actions ||= []).each do |action|
      if action[0] < now
        to_remove << action
        action[1].call
      end
    end
    @timeout_actions -= to_remove
  end

  def crystal_ready
    not @crystal_enabled and not @crystal_discharged
  end

  def future_action timeout_ms, _proc
    @timeout_actions << [Gosu.milliseconds + timeout_ms, _proc]
  end
  
  def enable_crystal
    @crystal_enabled = true
    @blocks.each { |k, block| compensate_mass block[:shape] }
    @timeout_actions ||= []
    future_action(5000, Proc.new do
      @blocks.each do |k, block|
        block[:shape].body.reset_forces
        @crystal_enabled = false
        @crystal_discharged = true
        future_action(5000, Proc.new do
          @crystal_discharged = false
        end)
      end
    end)
  end

  def button_down( id )
    if @letter_name
      case id
      when Gosu::KbSpace, Gosu::GpButton2
        @letter_name = nil
      end
    else
      p id
      case id
      when Gosu::KbLeft, Gosu::GpLeft
        @translation -= 1
      when Gosu::KbRight, Gosu::GpRight
        @translation = 1
      when Gosu::KbSpace, Gosu::GpButton2
        @character_shape.body.apply_impulse(v(0, -5000.0), v(0.0, 0.0)) if @touching_ground
      when Gosu::KbUp
        @up = true
      when 15 #r
        load_scene
      when 20 #b
        @bounding_boxes = !@bounding_boxes
      when 9 #e
        enable_crystal if crystal_ready
      when 52 #m
        if @music_instance.nil?
          @music_instance = @music.play(0.5, 1, true)
        else
          @music_instance.stop
          @music_instance = nil
        end
      when Gosu::KbEscape
        close
      end
    end
  end

  def button_up( id )
    @translation = 0
    @up = false
  end

end

IslandWindow.new.show
