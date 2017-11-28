#!/usr/bin/env ruby
class Object
  def __set(hash) hash.each { |k, v| send "#{k.to_s}=", v } end
  def dim() [width, height] end
end

require 'rubygems'
require 'gosu'
require 'chipmunk'
require 'yaml'
require 'dentaku'
include CP

class IslandWindow < Gosu::Window

  G = Vec2.new(0, 1000)
  CharaScale = 0.25

  def returning stuff
    yield stuff
    stuff
  end

  def v_limits w, h
    [[0, 0], [0, h], [w, h], [w, 0]].map { |x| Vec2.new(*x) }
  end

  def add_shape shape, u, collision_type
    shape.__set(u: u, collision_type: collision_type)
    @space.add_body shape.body
    returning(shape) { @space.add_shape shape }
  end

  def initialize_sensor_shape e, collision_type, object = nil
    returning(Shape::Poly.new Body.new(INFINITY, INFINITY), v_limits(*e[2..3]), Vec2.new(*e[0..1])) do |shape|
      shape.__set(collision_type: collision_type, sensor: true, object: object)
      @space.add_static_shape shape
    end
  end

  def initialize_letters
    @letters = Hash[(@scene["letters"] || []).map do |name, position|
                      [name, {shape: initialize_sensor_shape(position, :letter, name)}]
                    end]
  end

  def remove_shape_and_body shape, static = true
    static ?  @space.remove_static_shape(shape) : @space.remove_shape(shape)
    @space.remove_body shape.body
  end

  def delete_scene
    each_scene_shape(false) { |shape| remove_shape_and_body shape, shape.collision_type != :block }
    @decorations = []
    @timeout_actions = []
  end

  def load_scene
    %w(delete next initialize).each { |action| send "#{action}_scene" }
  end

  def letter_collision_callback letter_name
    letter = @letters[letter_name] || {}
    @letter_name = letter_name if not letter[:read]
    letter[:read] = true
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
      [:letter] => ->(l) { letter_collision_callback(l.object) },
    }.map { |k, v| k.each { |j| @space.add_collision_func(:character, j) { |c, o| v.call(o) }  } }
  end

  def initialize_physics
    @space = Space.new
    @space.__set(damping: 0.8, gravity: G)
    dim = @images[:character][0].dim.map { |x| x * CharaScale }
    @character_shape = Shape::Poly.new Body.new(10, INFINITY), v_limits(*dim), Vec2.new(0, 0)
    @character_shape.body.v_limit = 500
    add_shape @character_shape, 1.5, :character
  end

  def segment_shape pos, body
    body.pos = Vec2.new(*pos[0..1])
    Shape::Segment.new body, Vec2.new(0, 0), Vec2.new(pos[2] - pos[0], pos[3] - pos[1]), 3
  end

  def initialize_segment collision_type, conf, body = Body.new(INFINITY, INFINITY)
    returning(segment_shape conf["pos"], body) do |shape|
      shape.__set(collision_type: collision_type, u: 1.7, e: 0)
      yield shape
    end
  end

  def image_scale image, size
    size.each_with_index.map { |s, i| s.to_f / image.dim[i] }
  end

  def draw_exit
    @images[:stone_stack][0].draw(*@exit_shape.object[0..1], 0, 0.3, 0.3)
  end

  def initialize_platforms
    @platforms = {ground: @scene["platforms"], wall: @scene["walls"]}.map do |type, confs|
      confs.map { |k, conf| initialize_segment(type, conf) { |s| @space.add_static_shape s } }
    end.flatten
  end

  def merge_image name, conf
    image = Gosu::Image.new("media/#{name.sub(/-.*/, "")}.png")
    {scale: image_scale(image, (conf["size"] || image.dim)), image: image}.merge(conf)
  end

  def initialize_blocks
    @blocks = (@scene["blocks"] || []).map do |name, conf|
      [name, {shape: add_shape(Shape::Poly.new(
        Body.new(100, INFINITY), v_limits(*conf["size"][0..1]), Vec2.new(*conf["pos"])
      ), 1.7, :block)}.merge(merge_image(name, conf))]
    end
  end

  def initialize_decorations
    @decorations = @scene["decorations"].map do |k, conf|
      conf = {"pos"=>[0, 0]}.merge(conf.nil? ? {} : conf) if conf.nil? or conf["pos"].nil?
      [k, merge_image(k, conf)]
    end
  end

  def initialize_scene
    %w(platforms blocks letters decorations).each { |what| send "initialize_#{what}" }
    @exit_shape = initialize_sensor_shape @scene["exit"], :exit, @scene["exit"]
    @character_shape.body.p = Vec2.new(*@scene["entry"])
  end

  def next_scene
    @@scenes_path = 'scenes.yml'
    @level = YAML.load_file(@@scenes_path)["beach"]
    @scenes_mtime = File.mtime @@scenes_path
    @music ||= Gosu::Sample.new "media/#{@level["music"]}.ogg"
    @scene = @level["scenes"].values[@level_i ||= (ARGV[0] || 0).to_i]
    @letter = @letter_image = @letter_text = nil
    @crystal_status = :disabled
  end

  def initialize
    next_scene
    super(2400, 1600, false)
    @images = Hash[%i(characters character white_circle sheet letter stone_stack).map do |path|
                     [path, Dir.glob("media/#{path.to_s.sub(/s$/, "/*")}.png").map { |x| Gosu::Image.new(x) }]
                   end]
    %w(physics collisions_callbacks scene).each { |what| send "initialize_#{what}" }
    @t = @translation = 0
    @direction = 1
  end

  def ground_y pos
    @scene["platforms"].map { |_, v| v["pos"] }.reduce(0) do |b, plat|
      (plat[0] < pos[0] and pos[0] < plat[2]) ?  b + plat[1] : 0
    end
  end

  def draw_shadow scale, image, pos, direction = 1, from_ground = true
    y = from_ground ? 2 * (ground_y(pos) - image.height * scale[1]) - pos[1] : pos[1]
    image.draw_rot pos[0], y, 0, 180, 0, 2, -1.0 * scale[0] * direction, scale[1], 0x11_000000
  end

  def draw_crystal_power x, y, scale
    size = 3 * scale + (0.2 * scale * Math::sin(@t / 20))
    @images[:white_circle][0].draw(x, @character_shape.body.p.y, 0, size * @direction, size, 0x22_ff0000)
  end

  def move_character
    if @translation == 0
      @character = @images[:character][0]
    elsif @touching_ground
      @direction = @translation < 0 ? -1 : 1
      @character_shape.body.apply_impulse Vec2.new(@direction * 500.0, 0.0), Vec2.new(0.0, 0.0)
      @character = @images[:characters][Gosu.milliseconds / 100 % @images[:characters].size]
    end
  end

  def draw_character
    x = @direction == -1 ? @character_shape.bb.r : @character_shape.bb.l
    draw_crystal_power x, @character_shape.body.p.y, CharaScale if @crystal_status == :enabled
    @character.draw x, @character_shape.body.p.y, 0, CharaScale * @direction, CharaScale
    draw_shadow [CharaScale, CharaScale], @character, [x, @character_shape.body.p.y], @direction
  end

  def draw_bounding_box bb, color = Gosu::Color::RED
    points = [[bb.l, bb.t], [bb.r, bb.t], [bb.r, bb.b], [bb.l, bb.b]]
    points.each_with_index do |point, i|
      draw_line(*point, color, *points[(i + 1) % points.size], color)
    end
  end

  def draw_blocks
    @blocks.each do |k, conf|
      conf[:image].draw conf[:shape].bb.l, conf[:shape].bb.b, 0, *conf[:scale][0..1]
      draw_shadow conf[:scale], conf[:image], [conf[:shape].bb.l, conf[:shape].bb.b]
    end
  end

  def draw_decorations
    (@calculator ||= Dentaku::Calculator.new).store(t: @t.to_f)
    @decorations.each do |k, conf|
      pos = conf["pos"].map { |x| x.class == Integer ? x : @calculator.evaluate(x).to_f }
      scale = conf["scale"] || [1, 1]
      conf[:image].draw_rot(*pos[0..1], conf["z"] || 0, conf["angle"] || 0, 0, 0,
      *scale[0..1], conf["color"] || 0xff_ffffff)
      draw_shadow scale, conf[:image], pos, 1, false if not conf["shadow"].nil?
    end
  end

  def draw_letter
    return if @letter_name.nil?
    @images[:sheet][0].draw 500, 50, 0, 0.6, 0.6
    @letter ||= YAML.load_file('letters.yaml')["beach"]
    image = @letter["image"]
    @letter_image ||= Gosu::Image.new("media/#{image["name"]}.png")
    @letter_text ||= Gosu::Image.from_text(
      self, @letter["text"], "media/HelloPicasso.ttf", 70
    )
    @letter_text.draw 650, 100, 0, 1, 1, 0xff_000000
    @letter_image.draw(*image["pos"][0..1], 0, image["scale"], image["scale"])
  end

  def configuration_updated
    current_scenes_mtime = File.mtime @@scenes_path
    returning(@scenes_mtime < current_scenes_mtime) {@scenes_mtime = current_scenes_mtime}
  end

  def each_scene_shape(character_included=true)
    ([@letters, @blocks].map { |x| x.map { |k, o| o[:shape] } }.flatten +
     @platforms + (character_included ?[@character_shape]:[]) + [@exit_shape]).each { |s| yield s }
  end

  def draw
    run_timeout_actions
    move_character
    @touching_ground = false
    @space.step((1.0/60.0))
    %w(decorations exit character blocks letter).each { |what| send "draw_#{what}" }
    each_scene_shape{ |x| draw_bounding_box(x.bb) } if @bounding_boxes
    load_scene if (@t +=1) % 50 == 0 and configuration_updated
  end

  def compensate_mass shape
    shape.body.apply_force G * (- 1.00001 * shape.body.m), Vec2.new(0, 0)
    shape.body.p.y -= 1
  end

  def run_timeout_actions
    (@timeout_actions ||= []).select! do |action|
      returning(action[0] >= Gosu.milliseconds) { |keep| action[1].call if not keep }
    end
  end

  def timeout_action timeout_s, _proc
    (@timeout_actions||= []) << [Gosu.milliseconds + timeout_s * 1000, _proc]
  end

  def enable_crystal
    @crystal_status = :enabled
    @blocks.each { |k, block| compensate_mass block[:shape] }
    timeout_action(5, proc do
      @blocks.each { |k, block| block[:shape].body.reset_forces }
      @crystal_status = :discharged
      timeout_action(5, proc { @crystal_status = :disabled })
    end)
  end

  def mute_unmute
    @music_instance = @music_instance.nil? ? @music.play(0.5, 1, true) : @music_instance.stop
  end

  def on_space_or_button_2
    if @letter_name
      @letter_name = nil
    elsif @touching_ground
      @character_shape.body.apply_impulse(Vec2.new(0, -5000.0), Vec2.new(0.0, 0.0))
    end
  end

  def button_down id
    (@actions ||= {
      [Gosu::KbLeft, Gosu::GpLeft] => ->() { @translation = -1 },
      [Gosu::KbRight, Gosu::GpRight] => ->() { @translation = 1 },
      [Gosu::KbSpace, Gosu::GpButton2] => ->() { on_space_or_button_2 },
      [Gosu::KbUp] => ->() { @up = true },
      [15] => ->() {load_scene},
      [20] => ->() {@bounding_boxes = !@bounding_boxes},
      [9] => ->() {enable_crystal if @crystal_status == :disabled},
      [52] => ->() { mute_unmute },
      [Gosu::KbEscape] => ->() {close},
    }).each { |keys, action| return action.call if keys.include? id }
  end

  def button_up id
    @translation = 0
    @up = false
  end

end

IslandWindow.new.show
