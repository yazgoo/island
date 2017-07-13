#!/usr/bin/env ruby
require 'rubygems'
require 'gosu'
require 'chipmunk'
require 'pry'
require 'yaml'
require 'dentaku'

class IslandWindow < Gosu::Window

  def v2 a, b
    CP::Vec2.new a, b
  end

  def v_from_array a
    CP::Vec2.new a[0], a[1]
  end

  def unmovable_body
    CP::Body.new(CP::INFINITY, CP::INFINITY)
  end

  def initialize_platforms
    @platforms = @scene["platforms"].map do |k, v| 
      pos = v["pos"]
      platform_shape = CP::Shape::Segment.new(unmovable_body, v2(pos[0], pos[1]), v2(pos[2], pos[3]), 3) 
      platform_shape.collision_type = :ground
      # friction
      platform_shape.u = 1.5
      # elasticity
      platform_shape.e = 0
      @space.add_static_shape platform_shape
      platform_shape
    end
  end

  def v_limits w, h
    [[0, 0], [0, h], [w, h], [w, 0]].map { |x| v2 x[0], x[1]}
  end

  def initialize_exit
   e = @scene["exit"]
   @exit_shape = CP::Shape::Poly.new(unmovable_body, v_limits(e[2], e[3]), v2(e[0], e[1]))
   @exit_shape.collision_type = :exit
   @space.add_static_shape @exit_shape
  end

  def delete_scene
    @space.remove_shape @exit_shape
    @platforms.each { |platform| @space.remove_shape @platform }
    @decorations = []
  end

  def initialize_physics
    @space = CP::Space.new
    @space.damping = 0.8
    @space.gravity = v2(0, 1000)
    # infinite moment of inertia to make body non rotatable
    character_body = CP::Body.new(10, CP::INFINITY)
    w = @character_noframes.width * 0.25
    h = @character_noframes.height * 0.25
    @character_shape = CP::Shape::Poly.new(character_body, v_limits(w, h), v2(0, 0))
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

  def initialize_decorations
    @decorations = @scene["decorations"].map do |k, v|
      v = {"pos"=>[0, 0]}.merge(v.nil? ? {} : v) if v.nil? or v["pos"].nil?
      [k, {image: Gosu::Image.new("media/#{k}.png")}.merge(v)]
    end
  end

  def initialize_scene
    initialize_platforms
    @character_shape.body.p = v_from_array(@scene["entry"])
    initialize_exit
    initialize_decorations
  end

  def next_scene
    @level ||= YAML.load_file('scenes.yml')["beach"]
    @music ||= Gosu::Sample.new( self, "media/#{@level["music"]}.ogg")
    @level_i ||= 0
    scenes = @level["scenes"]
    @scene = scenes[scenes.keys[@level_i]]
  end

  def initialize
    next_scene
    super( 2400, 1600, false )
    @calculator = Dentaku::Calculator.new
    @music.play(0.5, 1, true)
    @character_frames = Dir.glob('media/character/*.png').map { |x| Gosu::Image.new(x) }
    @character_noframes = Gosu::Image.new('media/character.png')
    initialize_physics
    initialize_scene
    @t = 0
    @translation = 0
    @direction = 1
  end

  def draw_character
    if @translation == 0
      @character = @character_noframes
    elsif @touching_ground
      if @translation < 0
        @character_shape.body.apply_impulse(v2(-500.0, 0.0), v2(0.0, 0.0))
        @direction = -1 
      elsif @translation > 0
        @character_shape.body.apply_impulse(v2(500.0, 0.0), v2(0.0, 0.0))
        @direction = 1 
      end
      @character = @character_frames[@t % @character_frames.size]
    end
    x = @character_shape.bb.l
    x += @character_shape.bb.r - @character_shape.bb.l if @direction == -1
    @character.draw(x, @character_shape.body.p.y, 0, 0.25 * @direction, 0.25)
    @character.draw_rot(x, @character_shape.body.p.y, 0, 180, 0, 2, -0.25 * @direction, 0.25, 0x11_000000)
  end

  def draw_bounding_box shape
    a = shape.bb
    draw_line(a.l, a.t, Gosu::Color::RED, a.r, a.t, Gosu::Color::RED)
    draw_line(a.r, a.t, Gosu::Color::RED, a.r, a.b, Gosu::Color::RED)
    draw_line(a.r, a.b, Gosu::Color::RED, a.l, a.b, Gosu::Color::RED)
    draw_line(a.l, a.b, Gosu::Color::RED, a.l, a.t, Gosu::Color::RED)
  end

  def draw_decorations
    @calculator.store(t: @t.to_f)
    @decorations.each do |k, v|
      pos = v["pos"].map { |x| x.class == Fixnum ? x : @calculator.evaluate(x).to_f }
      color = v["color"]
      scale = v["scale"].nil? ? [1, 1] : v["scale"]
      v[:image].draw(pos[0], pos[1], 0, scale[0], scale[1], color.nil? ? 0xff_ffffff : color)
    end
  end

  def draw
    @touching_ground = false
    @space.step((1.0/60.0))
    @t += 1
    draw_decorations
    draw_character
    draw_bounding_box @character_shape
    draw_bounding_box @exit_shape
    @platforms.each { |platform| draw_bounding_box platform }
  end

  def button_down( id )
    case id
    when Gosu::KbLeft
      @translation -= 1
    when Gosu::KbRight
      @translation = 1
    when Gosu::KbUp
      @character_shape.body.apply_impulse(v2(0, -5000.0), v2(0.0, 0.0)) if @touching_ground
    when 8
      binding.pry
    when 41
      close
    end
  end

  def button_up( id )
    @translation = 0
  end

end

IslandWindow.new.show
