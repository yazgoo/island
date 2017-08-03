#!/usr/bin/env ruby
require 'rubygems'
require 'gosu'
require 'chipmunk'
require 'yaml'
require 'dentaku'
include CP

class Hash
  def get_or_else key, default
    self[key] || default
  end
end

class Shape::Segment
  def friction=(f) self.u = f end
  def elasticity=(e) self.e = e end
end

class IslandWindow < Gosu::Window

  def v a, b
    Vec2.new a, b
  end

  def v_from_array a
    v a[0], a[1]
  end

  def v_limits w, h
    [[0, 0], [0, h], [w, h], [w, 0]].map { |x| v x[0], x[1]}
  end

  def unmovable_body() Body.new(INFINITY, INFINITY) end

  def initialize_exit
   e = @scene["exit"]
   @exit_shape = Shape::Poly.new unmovable_body, v_limits(e[2], e[3]), v(e[0], e[1])
   @exit_shape.collision_type = :exit
   @space.add_static_shape @exit_shape
  end

  def remove_shape_and_body shape
    body = shape.body
    @space.remove_static_shape shape
    @space.remove_body body
  end

  def delete_scene
    remove_shape_and_body @exit_shape
    @platforms.each { |platform| remove_shape_and_body platform }
    @decorations = []
  end

  def initialize_physics
    @space = Space.new
    @space.damping = 0.8
    @space.gravity = v(0, 1000)
    character_body = Body.new 10, INFINITY  # infinite moment of inertia makes body non rotatable
    w = @character_noframes.width * 0.25
    h = @character_noframes.height * 0.25
    @character_shape = Shape::Poly.new character_body, v_limits(w, h), v(0, 0)
    @character_shape.collision_type = :character
    @character_shape.u = 1.5
    @space.add_body character_body
    @space.add_shape @character_shape
    @space.add_collision_func(:character, :ground) do |character, ground|
      @touching_ground = true
    end
    @space.add_collision_func(:character, :exit) do |character, ground|
      @space.add_post_step_callback(1) do 
        @level_i += 1
        delete_scene
        next_scene
        initialize_scene
      end
    end
  end

  def segment_shape conf, body
    pos = conf["pos"]
    body.pos = v(pos[0], pos[1])
    Shape::Segment.new body, v(0, 0), v(pos[2] - pos[0], pos[3] - pos[1]), 3
  end

  def initialize_segment collision_type, conf, body = unmovable_body
    shape = segment_shape conf, body
    shape.collision_type = collision_type
    shape.friction = 1.7
    shape.elasticity = 0
    yield shape
    shape
  end

  def initialize_segments collision_type, configuration
    configuration.map do |k, conf| 
      initialize_segment(collision_type, conf) { |s| @space.add_static_shape s }
    end
  end

  def initialize_platforms
    @platforms = {ground: @scene["platforms"], wall: @scene["walls"]}.map do |k, conf|
      initialize_segments k, conf
    end.flatten
  end

  def merge_image name, conf
    {image: Gosu::Image.new("media/#{name}.png")}.merge(conf)
  end

  def initialize_block conf
    body = Body.new 1000, INFINITY
    shape = segment_shape conf, body
    shape.collision_type = :block
    @space.add_shape shape
    shape
  end


  def initialize_blocks
    @blocks = @scene.get_or_else("blocks", []).map do |k, conf|
      [k, {shape: initialize_block(conf)}.merge(merge_image("block", conf))]
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
    @character_shape.body.p = v_from_array(@scene["entry"])
    initialize_exit
    initialize_decorations
  end

  def next_scene
    @level ||= YAML.load_file('scenes.yml')["beach"]
    @music ||= Gosu::Sample.new "media/#{@level["music"]}.ogg"
    @level_i ||= 0
    scenes = @level["scenes"]
    @scene = scenes[scenes.keys[@level_i]]
  end

  def initialize
    next_scene
    super( 2400, 1600, false )
    @calculator = Dentaku::Calculator.new
    @character_frames = Dir.glob('media/character/*.png').map { |x| Gosu::Image.new(x) }
    @character_noframes = Gosu::Image.new('media/character.png')
    initialize_physics
    initialize_scene
    @t = 0
    @translation = 0
    @direction = 1
  end

  def draw_shadow scale, image, pos, direction = 1
    image.draw_rot(pos[0], pos[1], 0, 180, 0, 2, -1.0 * scale[0] * direction, scale[1], 0x11_000000)
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
    @character.draw(x, @character_shape.body.p.y, 0, 0.25 * @direction, 0.25)
    draw_shadow [0.25, 0.25], @character, [x, @character_shape.body.p.y], @direction
  end

  def with(x) yield(x) end

  def draw_bounding_box shape, color = Gosu::Color::RED,
    points = with(shape.bb) { |a| [[a.l, a.t], [a.r, a.t], [a.r, a.b], [a.l, a.b]] }
    points.each_with_index do |point, i|
      n = (i + 1) % points.size
      draw_line point[0], point[1], color, points[n][0], points[n][1], color
    end
  end

  def draw_blocks
    @blocks.each do |k, conf|
      conf[:image].draw conf[:shape].bb.l, conf[:shape].bb.b, 0, 3, 3
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
        conf[:image].draw(pos[0], pos[1], z, scale[0], scale[1], color.nil? ? 0xff_ffffff : color)
      else
        conf[:image].draw_rot(pos[0], pos[1], z, conf["angle"], 0, 0, scale[0], scale[1], color.nil? ? 0xff_ffffff : color)
      end
      draw_shadow scale, conf[:image], pos if not conf["shadow"].nil?
    end
  end

  def draw
    @touching_ground = false
    @space.step((1.0/60.0))
    @t += 1
    draw_decorations
    draw_character
    draw_blocks
    if @bounding_boxes
      draw_bounding_box @character_shape
      draw_bounding_box @exit_shape
      @platforms.each { |platform| draw_bounding_box platform }
      @blocks.each { |k, block| draw_bounding_box block[:shape] }
    end
  end

  def translate_shape shape
    shape.body.apply_impulse v(0, -50000), v(0, 0)
  end
  
  def translate_blocks
    @blocks.each { |k, block| translate_shape block[:shape] }
  end

  def button_down( id )
    p id
    case id
    when Gosu::KbLeft, Gosu::GpLeft
      @translation -= 1
    when Gosu::KbRight, Gosu::GpRight
      @translation = 1
    when Gosu::KbUp, Gosu::GpButton2
      @character_shape.body.apply_impulse(v(0, -5000.0), v(0.0, 0.0)) if @touching_ground
    when 20 #b
      @bounding_boxes = !@bounding_boxes
    when 9 #e
      translate_blocks
    when 52 #m
      if @music_instance.nil?
        @music_instance = @music.play(0.5, 1, true)
      else
        @music_instance.stop
        @music_instance = nil
      end
    when 41 #escape
      close
    end
  end

  def button_up( id )
    @translation = 0
  end

end

IslandWindow.new.show
