#!/usr/bin/env ruby
require 'gtk3'
require 'time'
class Notifier
  SOUND_CANDIDATES = [
    '/usr/share/sounds/freedesktop/stereo/alarm-clock-elapsed.oga',
    '/usr/share/sounds/freedesktop/stereo/complete.oga',
    '/usr/share/sounds/freedesktop/stereo/bell.oga'
  ]

  def self.notify(title, body)
    if system('which notify-send >/dev/null 2>&1')
      system("notify-send \"#{escape(title)}\" \"#{escape(body)}\"")
    end
    puts "[NOTIFY] #{title}: #{body}"
  end

  def self.beep
    sound = SOUND_CANDIDATES.find { |p| File.exist?(p) }
    if sound && system('which paplay >/dev/null 2>&1')
      system("paplay #{sound} &")
    else
      print "\a" # beep do terminal
      $stdout.flush
    end
  end

  def self.escape(str)
    str.to_s.gsub('"', '\\"')
  end
end

class ClockTab < Gtk::Box
  attr_reader :switch_24h

  def initialize
    super(:vertical, 10)
    set_border_width(16)

    @time_label = Gtk::Label.new
    @time_label.name = 'time_label'
    @time_label.set_markup('<span size="64000" weight="bold">00:00:00</span>')
    @time_label.halign = :center

    @date_label = Gtk::Label.new
    @date_label.set_markup('<span size="20000">---</span>')
    @date_label.halign = :center

    row = Gtk::Box.new(:horizontal, 8)
    row.halign = :center
    row.pack_start(Gtk::Label.new('Formato 24h'), expand: false, fill: false, padding: 0)

    @switch_24h = Gtk::Switch.new
    @switch_24h.active = true
    row.pack_start(@switch_24h, expand: false, fill: false, padding: 0)

    pack_start(@time_label, expand: false, fill: false, padding: 0)
    pack_start(@date_label, expand: false, fill: false, padding: 0)
    pack_start(row, expand: false, fill: false, padding: 0)

    GLib::Timeout.add(200) { tick; true }
  end

  def tick
    now = Time.now
    format = @switch_24h.active? ? '%H:%M:%S' : '%I:%M:%S %p'
    @time_label.set_markup("<span size=\"64000\" weight=\"bold\">#{now.strftime(format)}</span>")
    @date_label.set_markup("<span size=\"20000\">#{now.strftime('%A, %d de %B de %Y')}</span>")
  end
end
class StopwatchTab < Gtk::Box
  def initialize
    super(:vertical, 8)
    set_border_width(16)

    @elapsed_ms = 0
    @running = false
    @last_tick = nil

    @display = Gtk::Label.new
    @display.set_markup('<span size="48000" weight="bold">00:00.000</span>')
    @display.halign = :center

    controls = Gtk::Box.new(:horizontal, 8)
    @btn_start = Gtk::Button.new(label: 'Iniciar')
    @btn_lap = Gtk::Button.new(label: 'Volta')
    @btn_reset = Gtk::Button.new(label: 'Zerar')

    @btn_lap.sensitive = false

    controls.pack_start(@btn_start, expand: false, fill: false, padding: 0)
    controls.pack_start(@btn_lap, expand: false, fill: false, padding: 0)
    controls.pack_start(@btn_reset, expand: false, fill: false, padding: 0)

    # Lista de voltas
    @store = Gtk::ListStore.new(Integer, String, String) # n, parcial, total
    @tree = Gtk::TreeView.new(@store)
    renderer = Gtk::CellRendererText.new
    col1 = Gtk::TreeViewColumn.new('#', renderer, text: 0)
    col2 = Gtk::TreeViewColumn.new('Parcial', renderer, text: 1)
    col3 = Gtk::TreeViewColumn.new('Total', renderer, text: 2)
    @tree.append_column(col1)
    @tree.append_column(col2)
    @tree.append_column(col3)
    scroller = Gtk::ScrolledWindow.new
    scroller.set_policy(:automatic, :automatic)
    scroller.add(@tree)
    scroller.set_min_content_height(160)

    pack_start(@display, expand: false, fill: false, padding: 0)
    pack_start(controls, expand: false, fill: false, padding: 0)
    pack_start(scroller, expand: true, fill: true, padding: 0)

    @btn_start.signal_connect('clicked') { toggle }
    @btn_lap.signal_connect('clicked') { lap }
    @btn_reset.signal_connect('clicked') { reset }

    GLib::Timeout.add(50) { tick; true }
  end

  def format_ms(ms)
    total_seconds = ms / 1000.0
    minutes = (total_seconds / 60).floor
    seconds = (total_seconds % 60).floor
    millis  = (ms % 1000)
    format('%02d:%02d.%03d', minutes, seconds, millis)
  end

  def tick
    if @running
      now = (Time.now.to_f * 1000).to_i
      delta = now - @last_tick
      @elapsed_ms += delta
      @last_tick = now
      @display.set_markup("<span size=\"48000\" weight=\"bold\">#{format_ms(@elapsed_ms)}</span>")
    end
  end

  def toggle
    if @running
      @running = false
      @btn_start.label = 'Retomar'
      @btn_lap.sensitive = false
    else
      @running = true
      @last_tick = (Time.now.to_f * 1000).to_i
      @btn_start.label = 'Pausar'
      @btn_lap.sensitive = true
    end
  end

  def lap
    return unless @running
    iter = @store.append
    n = @store.iter_n_children(nil)
    last_total = 0
    if n > 1
      # calcula parcial em relação à volta anterior
      prev_iter = @store.iter_nth_child(nil, n - 2)
      last_total_str = prev_iter[2]
      # converte "MM:SS.mmm" para ms
      mm, ss, mmm = last_total_str.match(/(\d+):(\d+)\.(\d+)/).captures.map(&:to_i)
      last_total = (mm * 60 + ss) * 1000 + mmm
    end
    parcial = @elapsed_ms - last_total
    iter[0] = n
    iter[1] = format_ms(parcial)
    iter[2] = format_ms(@elapsed_ms)
  end

  def reset
    @running = false
    @elapsed_ms = 0
    @btn_start.label = 'Iniciar'
    @btn_lap.sensitive = false
    @store.clear
    @display.set_markup('<span size="48000" weight="bold">00:00.000</span>')
  end
end

class TimerTab < Gtk::Box
  def initialize
    super(:vertical, 8)
    set_border_width(16)

    grid = Gtk::Grid.new
    grid.column_spacing = 6
    grid.row_spacing = 6

    @spin_h = Gtk::SpinButton.new(0, 99, 1)
    @spin_m = Gtk::SpinButton.new(0, 59, 1)
    @spin_s = Gtk::SpinButton.new(0, 59, 1)
    @spin_h.numeric = @spin_m.numeric = @spin_s.numeric = true

    grid.attach(Gtk::Label.new('Horas'), 0, 0, 1, 1)
    grid.attach(@spin_h, 1, 0, 1, 1)
    grid.attach(Gtk::Label.new('Min'), 2, 0, 1, 1)
    grid.attach(@spin_m, 3, 0, 1, 1)
    grid.attach(Gtk::Label.new('Seg'), 4, 0, 1, 1)
    grid.attach(@spin_s, 5, 0, 1, 1)

    @display = Gtk::Label.new
    @display.set_markup('<span size="36000" weight="bold">00:00:00</span>')
    @display.halign = :center

    @progress = Gtk::ProgressBar.new

    controls = Gtk::Box.new(:horizontal, 8)
    @btn_start = Gtk::Button.new(label: 'Iniciar')
    @btn_pause = Gtk::Button.new(label: 'Pausar')
    @btn_reset = Gtk::Button.new(label: 'Zerar')
    @btn_pause.sensitive = false

    controls.pack_start(@btn_start, expand: false, fill: false, padding: 0)
    controls.pack_start(@btn_pause, expand: false, fill: false, padding: 0)
    controls.pack_start(@btn_reset, expand: false, fill: false, padding: 0)

    pack_start(grid, expand: false, fill: false, padding: 0)
    pack_start(@display, expand: false, fill: false, padding: 0)
    pack_start(@progress, expand: false, fill: false, padding: 0)
    pack_start(controls, expand: false, fill: false, padding: 0)

    @total_ms = 0
    @remaining_ms = 0
    @running = false
    @last_tick = nil

    @btn_start.signal_connect('clicked') { start }
    @btn_pause.signal_connect('clicked') { pause }
    @btn_reset.signal_connect('clicked') { reset }

    GLib::Timeout.add(50) { tick; true }
  end

  def mmss(ms)
    tot = (ms / 1000.0).ceil
    h = tot / 3600
    m = (tot % 3600) / 60
    s = tot % 60
    format('%02d:%02d:%02d', h, m, s)
  end

  def start
    if !@running
      @total_ms = ((@spin_h.value_as_int * 3600) + (@spin_m.value_as_int * 60) + @spin_s.value_as_int) * 1000
      if @total_ms <= 0 && @remaining_ms <= 0
        Notifier.notify('Temporizador', 'Defina um tempo maior que zero.')
        return
      end
      @remaining_ms = @total_ms if @remaining_ms <= 0
      @running = true
      @last_tick = (Time.now.to_f * 1000).to_i
      @btn_pause.sensitive = true
    end
  end

  def pause
    @running = false
  end

  def reset
    @running = false
    @total_ms = 0
    @remaining_ms = 0
    @progress.fraction = 0.0
    @display.set_markup('<span size="36000" weight="bold">00:00:00</span>')
  end

  def tick
    if @running
      now = (Time.now.to_f * 1000).to_i
      delta = now - @last_tick
      @last_tick = now
      @remaining_ms -= delta
      @remaining_ms = 0 if @remaining_ms < 0
      @display.set_markup("<span size=\"36000\" weight=\"bold\">#{mmss(@remaining_ms)}</span>")
      if @total_ms > 0
        @progress.fraction = 1.0 - (@remaining_ms.to_f / @total_ms)
      end
      if @remaining_ms <= 0
        @running = false
        Notifier.beep
        Notifier.notify('Temporizador', 'Tempo esgotado!')
      end
    end
  end
end

class AlarmsTab < Gtk::Box
  Alarm = Struct.new(:hour, :min, :label, :enabled, :fired_today)

  def initialize
    super(:vertical, 8)
    set_border_width(16)

    @store = Gtk::ListStore.new(String, String, TrueClass)
    @tree = Gtk::TreeView.new(@store)
    renderer_text = Gtk::CellRendererText.new
    renderer_toggle = Gtk::CellRendererToggle.new
    renderer_toggle.activatable = true

    col_time = Gtk::TreeViewColumn.new('Hora', renderer_text, text: 0)
    col_label = Gtk::TreeViewColumn.new('Rótulo', renderer_text, text: 1)
    col_enabled = Gtk::TreeViewColumn.new('Ativo', renderer_toggle, active: 2)

    @tree.append_column(col_time)
    @tree.append_column(col_label)
    @tree.append_column(col_enabled)

    renderer_toggle.signal_connect('toggled') do |_, path|
      iter = @store.get_iter(path)
      iter[2] = !iter[2]
    end

    scroller = Gtk::ScrolledWindow.new
    scroller.set_policy(:automatic, :automatic)
    scroller.add(@tree)
    scroller.set_min_content_height(180)

    controls = Gtk::Box.new(:horizontal, 8)
    @btn_add = Gtk::Button.new(label: 'Adicionar')
    @btn_del = Gtk::Button.new(label: 'Remover')
    controls.pack_start(@btn_add, expand: false, fill: false, padding: 0)
    controls.pack_start(@btn_del, expand: false, fill: false, padding: 0)

    pack_start(scroller, expand: true, fill: true, padding: 0)
    pack_start(controls, expand: false, fill: false, padding: 0)

    @btn_add.signal_connect('clicked') { add_dialog }
    @btn_del.signal_connect('clicked') { remove_selected }

    @last_day = Date.today

    GLib::Timeout.add(500) { tick; true }
  end

  def add_dialog
    dialog = Gtk::Dialog.new(title: 'Novo Alarme', flags: :modal)
    dialog.add_button('Cancelar', :cancel)
    dialog.add_button('Adicionar', :ok)

    box = dialog.child
    grid = Gtk::Grid.new
    grid.column_spacing = 6
    grid.row_spacing = 6

    spin_h = Gtk::SpinButton.new(0, 23, 1)
    spin_m = Gtk::SpinButton.new(0, 59, 1)
    entry_label = Gtk::Entry.new
    entry_label.placeholder_text = 'Rótulo (opcional)'

    grid.attach(Gtk::Label.new('Hora'), 0, 0, 1, 1)
    grid.attach(spin_h, 1, 0, 1, 1)
    grid.attach(Gtk::Label.new('Min'), 2, 0, 1, 1)
    grid.attach(spin_m, 3, 0, 1, 1)
    grid.attach(Gtk::Label.new('Rótulo'), 0, 1, 1, 1)
    grid.attach(entry_label, 1, 1, 3, 1)

    box.add(grid)
    dialog.show_all

    if dialog.run == Gtk::ResponseType::OK
      time_str = format('%02d:%02d', spin_h.value_as_int, spin_m.value_as_int)
      iter = @store.append
      iter[0] = time_str
      iter[1] = entry_label.text.to_s
      iter[2] = true
    end
    dialog.destroy
  end

  def remove_selected
    sel = @tree.selection
    if iter = sel.selected
      @store.remove(iter)
    end
  end

  def tick
    today = Date.today
    if today != @last_day
      @last_day = today
    end

    now = Time.now
    current = now.strftime('%H:%M')

    @store.each do |model, path, iter|
      next unless iter[2] # ativo
      if iter[0] == current
        key = current + now.strftime(':%S')
        unless @last_fire_key == key
          @last_fire_key = key
          Notifier.beep
          Notifier.notify('Alarme', iter[1].to_s.empty? ? "Alarme #{current}" : iter[1])
        end
      end
    end
  end
end

class ClockApp < Gtk::Application
  def initialize
    super('br.com.exemplo.relogio', :flags_none)
    signal_connect 'activate' do |app|
      window = Gtk::ApplicationWindow.new(app)
      window.set_title('Relógio (Ruby + GTK3)')
      window.set_default_size(560, 480)

      header = Gtk::HeaderBar.new
      header.title = 'Relógio'
      header.subtitle = 'Digital • Cronômetro • Temporizador • Alarmes'
      header.show_close_button = true
      window.set_titlebar(header)

      notebook = Gtk::Notebook.new
      clock = ClockTab.new
      stopwatch = StopwatchTab.new
      timer = TimerTab.new
      alarms = AlarmsTab.new

      notebook.append_page(clock, Gtk::Label.new('Relógio'))
      notebook.append_page(stopwatch, Gtk::Label.new('Cronômetro'))
      notebook.append_page(timer, Gtk::Label.new('Temporizador'))
      notebook.append_page(alarms, Gtk::Label.new('Alarmes'))

      window.add(notebook)
      window.show_all
    end
  end
end
app = ClockApp.new
app.run([$0] + ARGV)
