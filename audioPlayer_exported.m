classdef audioPlayer_exported < matlab.apps.AppBase

    % Properties that correspond to app components
    properties (Access = public)
        UIFigure               matlab.ui.Figure
        GridLayout             matlab.ui.container.GridLayout
        Panel_2                matlab.ui.container.Panel
        VolumeLabel            matlab.ui.control.Label
        VolumeKnob             matlab.ui.control.Knob
        VolumeKnobLabel        matlab.ui.control.Label
        ReverseLamp            matlab.ui.control.Lamp
        ReversedLampLabel      matlab.ui.control.Label
        ReverseSwitch          matlab.ui.control.Switch
        TabGroup               matlab.ui.container.TabGroup
        FilterTab              matlab.ui.container.Tab
        GridLayout2            matlab.ui.container.GridLayout
        Panel_9                matlab.ui.container.Panel
        LPFLabel               matlab.ui.control.Label
        LPFCutKnob             matlab.ui.control.Knob
        LPFCutKnobLabel        matlab.ui.control.Label
        Panel_5                matlab.ui.container.Panel
        HPFLabel               matlab.ui.control.Label
        HPFCutKnob             matlab.ui.control.Knob
        HPFCutKnobLabel        matlab.ui.control.Label
        Panel_3                matlab.ui.container.Panel
        HPFSwitch              matlab.ui.control.Switch
        HPFSwitchLabel         matlab.ui.control.Label
        HPFLamp                matlab.ui.control.Lamp
        LPFLamp                matlab.ui.control.Lamp
        LPFSwitch              matlab.ui.control.Switch
        LPFSwitchLabel         matlab.ui.control.Label
        UIAxesFilterResponse   matlab.ui.control.UIAxes
        TremoloTab             matlab.ui.container.Tab
        GridLayout3            matlab.ui.container.GridLayout
        Panel_11               matlab.ui.container.Panel
        DepthKnob              matlab.ui.control.Knob
        DepthKnobLabel         matlab.ui.control.Label
        DepthLabel             matlab.ui.control.Label
        Panel_10               matlab.ui.container.Panel
        RateKnob               matlab.ui.control.Knob
        RateKnobLabel          matlab.ui.control.Label
        RateLabel              matlab.ui.control.Label
        Panel_6                matlab.ui.container.Panel
        TremoloSwitch          matlab.ui.control.Switch
        TremoloSwitchLabel     matlab.ui.control.Label
        TremoloLamp            matlab.ui.control.Lamp
        UIAxesTremoloLFO       matlab.ui.control.UIAxes
        Panel                  matlab.ui.container.Panel
        TimerLabel             matlab.ui.control.Label
        SampleRateEditField    matlab.ui.control.NumericEditField
        SampleRateSlider       matlab.ui.control.Slider
        SampleRateSliderLabel  matlab.ui.control.Label
        PlayButton             matlab.ui.control.Button
        LoadFileButton         matlab.ui.control.Button
        UIAxesTimeDomain       matlab.ui.control.UIAxes
        UIAxesSpectrogram      matlab.ui.control.UIAxes
    end

    % Public properties that correspond to the Simulink model
    properties (Access = public, Transient)
        Simulation simulink.Simulation
    end

    
    properties (Access = private)
        AudioData           % loaded signal
        ProcessedData       % processed signal
        Fs= 96000           % sample rate
        RedLine             % redline follower
        DeviceWriter        % Audio Player
        IsPlaying           % flag playing/ not playing
        CurrentSample = 1   % index to follow the current sample
        MaxRefDB = 0
        % Real Time Variables
        volume = 50
        lfo_rate = 5
        lfo_depth = 0.8
        % DSP Memory
        % filter state memory
        b_coef_HPF = 1; a_coef_HPF = 1; filterState_HPF = [];  % HPF
        b_coef_LPF = 1; a_coef_LPF = 1; filterState_LPF = [];  % LPF
        lfoPhase = 0        % lfo phase state memory
        ReversedData        % reversed signal
    end
    
    methods (Access = private)

        %% ========================================================================
        %% Functions - Calculate Filter Coefficient & Draw Small graphs
        %% ========================================================================

        function updateFilterCoeffs(app,hpf_val,lpf_val)
            % drawPlot determines if we just calculate (live) or also draw
            % If there is no event from interface, take the current values
            % of the filter buttons
            if nargin <2, hpf_val = app.HPFCutKnob.Value; end
            if nargin < 3, lpf_val = app.LPFCutKnob.Value; end
            if isempty(app.Fs) 
                return; 
            end

            fn = app.Fs / 2; % Nyquist Frequency

            % Calculate HPF Coeffs
            if strcmp(app.HPFSwitch.Value,'On')
                fc_hpf = 10^hpf_val;
                if fc_hpf <= 0, fc_hpf = 1; elseif fc_hpf >= fn, fc_hpf = fn -1; end
                [app.b_coef_HPF,app.a_coef_HPF] = butter (4,fc_hpf/fn,'high');
            else
                app.b_coef_HPF = 1; app.a_coef_HPF = 1; % Bypass (No filtering)
            end

            % Calculate LPF Coeffs
            if strcmp(app.LPFSwitch.Value,'On')
                fc_lpf = 10^lpf_val;
                if fc_lpf <= 0, fc_lpf = 1; elseif fc_lpf >= fn, fc_lpf = fn -1; end
                [app.b_coef_LPF,app.a_coef_LPF] = butter (4,fc_lpf/fn,'low');
            else
                app.b_coef_LPF = 1; app.a_coef_LPF = 1; % Bypass (No filtering)
            end

            % Bode Plot
            [H_hpf,f] = freqz(app.b_coef_HPF,app.a_coef_HPF,2048,app.Fs);
            [H_lpf,~] = freqz(app.b_coef_LPF,app.a_coef_LPF,2048,app.Fs);
            H_total = H_hpf .* H_lpf; % Cascading two filter in series
            mag_dB = 20*log10(abs(H_total) + eps);

            if strcmp(app.HPFSwitch.Value,'On') || strcmp(app.LPFSwitch.Value,'On')
                plotColor = '#D95319';  % orange color, On
            else
                plotColor = '#A2A2A2';  % gray, Off
            end

            semilogx(app.UIAxesFilterResponse,f,mag_dB,'LineWidth',2,'Color',plotColor);
            xlim(app.UIAxesFilterResponse, [20, fn]);
            ylim(app.UIAxesFilterResponse, [-80, 5]);
            freqTicks = [20, 50, 100, 200, 500, 1000, 2000, 5000, 10000, 20000];
            freqTicks = freqTicks(freqTicks <= fn);
            app.UIAxesFilterResponse.XTick = freqTicks;
            app.UIAxesFilterResponse.XTickLabel = arrayfun(@(f) app.formatFreq(f), freqTicks, 'UniformOutput', false);
            app.UIAxesFilterResponse.YTick = [-80, -60, -40, -20, -12, -6, 0];
            app.UIAxesFilterResponse.YTickLabel = {'-80','-60','-40','-20','-12','-6','0'};
            grid(app.UIAxesFilterResponse, 'on');


        end

        function updateLFOPlot(app)
            if isempty(app.Fs),return; end
            rate = app.lfo_rate;
            depth = app.lfo_depth;
            t_lfo = linspace(0,1,app.Fs); % one second window
            lfo_vis = (1-depth) + depth*(sin(2*pi*rate*t_lfo) + 1)/2; % amplitude envelope

            % Plot Tremolo Waveform
            if strcmp(app.TremoloSwitch.Value,'On')
                plotColor = '#0072BD';  % blue color, On
            else
                plotColor = '#A2A2A2';  % gray, Off
            end
                
            plot(app.UIAxesTremoloLFO,t_lfo,lfo_vis,'LineWidth',2,'Color',plotColor);

            app.UIAxesTremoloLFO.Title.String = 'LFO Envelope (Amplitude Modulation)';
            app.UIAxesTremoloLFO.XLabel.String = 'Time (1 Second Window)';
            app.UIAxesTremoloLFO.YLabel.String = 'Gain (Multiplier)';
            ylim(app.UIAxesTremoloLFO, [0, 1.1]);
            cycleLen = 1 / max(0.1, app.lfo_rate); % Prevent division by zero
            numCycles = floor(1 / cycleLen);
            xTicks = (0 : numCycles) * cycleLen;
            xTicks = xTicks(xTicks <= 1);
            app.UIAxesTremoloLFO.XTick = xTicks;
            app.UIAxesTremoloLFO.XTickLabel = arrayfun(@(x) sprintf('%.2f', x), xTicks, 'UniformOutput', false);
            app.UIAxesTremoloLFO.YTick = [0, 0.25, 0.5, 0.75, 1];
            app.UIAxesTremoloLFO.YTickLabel = {'0','0.25','0.5','0.75','1'};
            grid(app.UIAxesTremoloLFO, 'on');
        end

        function updateSmallGraphs(app)
            app.updateLFOPlot();
            app.updateFilterCoeffs();
        end

        %% ========================================================================
        %% Offline process engine - For the Big Data
        %% ========================================================================

        function deviceName = getCurrentAudioDevice(~)
            try
                info = audiodevinfo;
                % get the default audio device
                for i = 1:length(info.output)
                    if info.output(i).DefaultSampleRate > 0
                        deviceName = info.output(i).Name;
                        return;
                    end
                end
                deviceName = 'default';
            catch
                deviceName = 'default';
            end
        end

        function createAudioDeviceWriter(app)
            if ~isempty(app.DeviceWriter)
                try
                    release(app.DeviceWriter);
                catch
                end
            end
            deviceName = app.getCurrentAudioDevice();
            app.DeviceWriter = audioDeviceWriter( ... 
                'SampleRate',app.Fs,...
                'SupportVariableSizeInput',true,...
                'BufferSize',1024,...
                'Device',deviceName);
        
        end

        function applyDSP(app)
            % stage 1: always update calculations and small graphs
            app.updateFilterCoeffs();
            app.updateLFOPlot();
            
            % stage 2: if file not loaded to memory
            if isempty(app.AudioData)
                return;
            end

            % stage 3: offline processing, applying the DSP
            tempSignal = app.AudioData;

            if strcmp(app.ReverseSwitch.Value,'On')
                tempSignal = app.ReversedData;
            end
            if strcmp(app.HPFSwitch.Value, 'On')
                tempSignal = filter(app.b_coef_HPF, app.a_coef_HPF,tempSignal);
            end
            if strcmp(app.LPFSwitch.Value, 'On')
                tempSignal = filter(app.b_coef_LPF, app.a_coef_LPF,tempSignal);
            end
            if strcmp(app.TremoloSwitch.Value,'On')
                rate = app.lfo_rate;
                depth = app.lfo_depth;
                t_full = (0:length(tempSignal) - 1).' / app.Fs;
                lfo_full = (1-depth) + depth*(sin(2*pi*rate*t_full) + 1)/2;
                tempSignal = tempSignal .* lfo_full;
            end

            % stage 4: Store and Plot Graphs
            app.ProcessedData = tempSignal;
            app.updateMainVisuals();
        end

        function updateMainVisuals(app)
            if isempty(app.ProcessedData)
                return;
            end

            % Plot Time-Domain
            t = (0:length(app.ProcessedData) - 1) / app.Fs;
            cla(app.UIAxesTimeDomain);
            plot(app.UIAxesTimeDomain,t,app.ProcessedData,'blue');
            xlim(app.UIAxesTimeDomain, [0, max(t)]);
            app.UIAxesTimeDomain.Title.String = 'Time Domain Signal';
            app.UIAxesTimeDomain.XLabel.String = 'Time (s)';
            app.UIAxesTimeDomain.YLabel.String = 'Amplitude';
            ylim(app.UIAxesTimeDomain, [-1.1, 1.1]);
            app.UIAxesTimeDomain.YTick = [-1, -0.5, 0, 0.5, 1];
            app.UIAxesTimeDomain.YTickLabel = {'-1', '-0.5', '0', '0.5', '1'};
            grid(app.UIAxesTimeDomain,'on');

            % Red Line that follow playback
            if app.CurrentSample > 0 && app.CurrentSample <= length(app.ProcessedData)
                currentTime = (app.CurrentSample - 1) / app.Fs;
            else
                currentTime = 0;
            end
            app.RedLine = xline(app.UIAxesTimeDomain,currentTime, 'r', 'LineWidth',2);

            % Plot the Spectogram
            windowLength = 1024; overlap = 512; nfft = 1024;
            [S, F, T] = spectrogram(app.ProcessedData, windowLength, overlap,nfft, app.Fs);
            S_dB = 10 * log10(abs(S) + eps);
            
            cla(app.UIAxesSpectrogram);
            imagesc(app.UIAxesSpectrogram, T, F, S_dB);
            app.UIAxesSpectrogram.YDir = 'normal';
            ylim(app.UIAxesSpectrogram, [0, min(20000, app.Fs/2)]);
            freqTicks = [0, 500, 1000, 2000, 4000, 8000, 16000, 20000];
            freqTicks = freqTicks(freqTicks <= min(20000, app.Fs/2));
            app.UIAxesSpectrogram.YTick = freqTicks;
            app.UIAxesSpectrogram.YTickLabel = arrayfun(@(f) app.formatFreq(f), freqTicks, 'UniformOutput', false);
            if app.MaxRefDB == 0
                app.MaxRefDB = max(S_dB(:));
            end
            clim(app.UIAxesSpectrogram, [app.MaxRefDB - 60, app.MaxRefDB]);
            colormap(app.UIAxesSpectrogram, 'jet');
            app.UIAxesSpectrogram.Title.String = 'Spectrogram (Time-Frequency)';
            app.UIAxesSpectrogram.XLabel.String = 'Time (s)';
            app.UIAxesSpectrogram.YLabel.String = 'Frequency (Hz)';
            xlim(app.UIAxesSpectrogram, [0, max(T)]);

        end

        %% ========================================================================
        %% Live Play Engine
        %% ========================================================================

        function chunk = processLiveChunk(app, startIdx, endIdx)
            % fetch next 1024 samples
            if strcmp(app.ReverseSwitch.Value,'On')
                chunk = app.ReversedData(startIdx : endIdx);
            else
                chunk = app.AudioData(startIdx : endIdx);
            end

            % High Pass Filter with Continous state store
            if strcmp(app.HPFSwitch.Value,'On')
                stateSize = max(length(app.a_coef_HPF)-1 , length(app.b_coef_HPF) -1);
                if isempty(app.filterState_HPF) || length(app.filterState_HPF) ~= stateSize
                    app.filterState_HPF = zeros(stateSize,1);
                end
                [chunk, app.filterState_HPF] = filter(app.b_coef_HPF,app.a_coef_HPF,chunk, app.filterState_HPF);
            else
                app.filterState_HPF = [];
            end

            % Low Pass Filter with Continous state store
            if strcmp(app.LPFSwitch.Value,'On')
                stateSize = max(length(app.a_coef_LPF)-1 , length(app.b_coef_LPF) -1);
                if isempty(app.filterState_LPF) || length(app.filterState_LPF) ~= stateSize
                    app.filterState_LPF = zeros(stateSize,1);
                end
                [chunk, app.filterState_LPF] = filter(app.b_coef_LPF,app.a_coef_LPF,chunk, app.filterState_LPF);
            else
                app.filterState_LPF = [];
            end

            % Tremolo with phase state store
            if strcmp(app.TremoloSwitch.Value,'On')
                rate = app.lfo_rate;
                depth = app.lfo_depth;
                t_chunk = (0:length(chunk)-1).' / app.Fs;
                phases = 2*pi*rate*t_chunk + app.lfoPhase;

                lfo = (1-depth) + depth*(sin(phases) + 1)/2; % countinous envelope waveform
                chunk = chunk .* lfo;
                app.lfoPhase = mod(phases(end) + 2*pi*rate/app.Fs, 2*pi); % store phase for next buffer
            else
                app.lfoPhase = 0;
            end

            % Volume
            gain = app.volume / 50;
            chunk = chunk * gain;
        end
        
        
        function label = formatFreq(~,freq)
            if freq>= 1000
                label = sprintf('%.0fk', freq/1000);
            else
                label = sprintf('%.0f',freq);
            end
        end

        
    end
    

    % Callbacks that handle component events
    methods (Access = private)

        % Code that executes after component creation
        function startupFcn(app)
            % app.UIFigure.Resize = 'off';
            myInteractions = [panInteraction('Dimensions','x'),...
                                zoomInteraction('Dimensions','x'), ...
                                dataTipInteraction()];
            
            app.UIAxesTimeDomain.Interactions = myInteractions;
            app.UIAxesSpectrogram.Interactions = myInteractions;
            app.UIAxesFilterResponse.Interactions = myInteractions;
            app.UIAxesTremoloLFO.Interactions = myInteractions;
            
            % Redesign the graphs toolbar
            axesList = [app.UIAxesTimeDomain, app.UIAxesSpectrogram, ...
                        app.UIAxesFilterResponse, app.UIAxesTremoloLFO];
            for ax = axesList
                % delete all toolbar icons and add only restore button
                axtoolbar(ax, {'restoreview'}); 
            end
            % ----------

            c = colorbar(app.UIAxesSpectrogram);
            c.Label.String = 'Magnitude (dB)';

            % Time Domain
            app.UIAxesTimeDomain.Title.String = 'Time Domain Signal';
            app.UIAxesTimeDomain.XLabel.String = 'Time (s)';
            app.UIAxesTimeDomain.YLabel.String = 'Amplitude';
            ylim(app.UIAxesTimeDomain, [-1.1, 1.1]);
            app.UIAxesTimeDomain.YTick = [-1, -0.5, 0, 0.5, 1];
            app.UIAxesTimeDomain.YTickLabel = {'-1', '-0.5', '0', '0.5', '1'};
            grid(app.UIAxesTimeDomain,'on');

            % Spectogram
            app.UIAxesSpectrogram.Title.String = 'Spectrogram (Time-Frequency)';
            app.UIAxesSpectrogram.XLabel.String = 'Time (s)';
            app.UIAxesSpectrogram.YLabel.String = 'Frequency (Hz)';
            app.UIAxesSpectrogram.YDir = 'normal';
            colormap(app.UIAxesSpectrogram, 'jet');
            ylim(app.UIAxesSpectrogram, [0, min(20000, app.Fs/2)]);
            freqTicks = [0, 500, 1000, 2000, 4000, 8000, 16000, 20000];
            freqTicks = freqTicks(freqTicks <= min(20000, app.Fs/2));
            app.UIAxesSpectrogram.YTick = freqTicks;
            app.UIAxesSpectrogram.YTickLabel = arrayfun(@(f) app.formatFreq(f), freqTicks, 'UniformOutput', false);

            % init limits and fix Major Ticks
            app.HPFCutKnob.Limits = [log10(20), log10(20000)];
            app.HPFCutKnob.MajorTicks = log10([20, 200, 2000, 20000]);
            app.HPFCutKnob.MajorTickLabels = {'20', '200', '2k', '20k'};

            app.LPFCutKnob.Limits = [log10(20), log10(20000)];
            app.LPFCutKnob.MajorTicks = log10([20, 200, 2000, 20000]);
            app.LPFCutKnob.MajorTickLabels = {'20', '200', '2k', '20k'};

            app.RateKnob.Limits = [0.1, 15]; 
            app.DepthKnob.Limits = [0, 1]; 
            app.VolumeKnob.Limits = [0, 100];

            % init values
            app.SampleRateEditField.Value = app.Fs;
            app.HPFCutKnob.Value = log10(300);
            app.LPFCutKnob.Value = log10(8000);
            app.RateKnob.Value = 5;
            app.DepthKnob.Value = 0.8;
            app.VolumeKnob.Value = 50;

            % update plots
            app.updateFilterCoeffs(app.HPFCutKnob.Value,app.LPFCutKnob.Value);
            app.updateLFOPlot();
            app.applyDSP();

            % init lamps colors
            app.ReverseLamp.Color = 'black';
            app.HPFLamp.Color = 'black';
            app.LPFLamp.Color = 'black';
            app.TremoloLamp.Color = 'black';
            
            % init labels text
            app.VolumeLabel.Text = '50 %';
            app.RateLabel.Text = '5.0 Hz';
            app.DepthLabel.Text = '0.80';
            app.HPFLabel.Text = '300 Hz';
            app.LPFLabel.Text = '8000 Hz';

            % switch on/off label data
            app.ReverseSwitch.Items = {' ', '  '};
            app.ReverseSwitch.ItemsData = {'Off', 'On'};
            app.HPFSwitch.Items = {' ', '  '};
            app.HPFSwitch.ItemsData = {'Off', 'On'};
            app.LPFSwitch.Items = {' ', '  '};
            app.LPFSwitch.ItemsData = {'Off', 'On'};
            app.TremoloSwitch.Items = {' ', '  '};
            app.TremoloSwitch.ItemsData = {'Off', 'On'};

        end

        % Value changed function: SampleRateSlider
        function SampleRateSliderValueChanged(app, event)
            app.Fs = event.Value;
            app.SampleRateEditField.Value = app.Fs;
            app.createAudioDeviceWriter();
            app.applyDSP();
        end

        % Value changed function: ReverseSwitch
        function ReverseSwitchValueChanged(app, event)
            if strcmp(app.ReverseSwitch.Value,'On')
                app.ReverseLamp.Color = 'green';
            else
                app.ReverseLamp.Color = 'black';
            end
            app.applyDSP();
     
        end

        % Value changed function: LPFSwitch
        function LPFSwitchValueChanged(app, event)
            if strcmp(app.LPFSwitch.Value,'On')
                app.LPFLamp.Color = 'green';
            else
                app.LPFLamp.Color = 'black';
            end
            app.updateSmallGraphs();
            app.applyDSP();
            
        end

        % Value changed function: HPFSwitch
        function HPFSwitchValueChanged(app, event)
            if strcmp(app.HPFSwitch.Value,'On')
                app.HPFLamp.Color = 'green';
            else
                app.HPFLamp.Color = 'black';
            end
            app.updateSmallGraphs();
            app.applyDSP();

        end

        % Value changed function: TremoloSwitch
        function TremoloSwitchValueChanged(app, event)
            if strcmp(app.TremoloSwitch.Value, 'On')
                app.TremoloLamp.Color = 'green';
            else
                app.TremoloLamp.Color = 'black';
            end
            app.updateSmallGraphs();
            app.applyDSP();
            
        end

        % Value changing function: VolumeKnob
        function VolumeKnobValueChanging(app, event)
            app.volume = event.Value;
            app.VolumeLabel.Text = sprintf('%.0f %%', event.Value);
            
        end

        % Value changed function: VolumeKnob
        function VolumeKnobValueChanged(app, event)
            app.volume = app.VolumeKnob.Value;

        end

        % Value changing function: LPFCutKnob
        function LPFCutKnobValueChanging(app, event)
            app.LPFLabel.Text = app.formatFreq(10^event.Value);
            app.updateFilterCoeffs(app.HPFCutKnob.Value,event.Value);
            
        end

        % Value changed function: LPFCutKnob
        function LPFCutKnobValueChanged(app, event)
            app.applyDSP();
            app.updateFilterCoeffs(app.HPFCutKnob.Value,app.LPFCutKnob.Value);
            
        end

        % Value changing function: HPFCutKnob
        function HPFCutKnobValueChanging(app, event)
            app.HPFLabel.Text = app.formatFreq(10^event.Value);
            app.updateFilterCoeffs(event.Value,app.LPFCutKnob.Value);
            
        end

        % Value changed function: HPFCutKnob
        function HPFCutKnobValueChanged(app, event)
            app.applyDSP();
            app.updateFilterCoeffs(app.HPFCutKnob.Value,app.LPFCutKnob.Value);
            
        end

        % Value changing function: RateKnob
        function RateKnobValueChanging(app, event)
            app.lfo_rate = event.Value;
            app.RateLabel.Text = sprintf('%.1f Hz',event.Value);
            app.updateLFOPlot();
            
        end

        % Value changed function: RateKnob
        function RateKnobValueChanged(app, event)
            app.lfo_rate = app.RateKnob.Value;
            app.applyDSP();
            
        end

        % Value changing function: DepthKnob
        function DepthKnobValueChanging(app, event)
            app.lfo_depth = event.Value;
            app.DepthLabel.Text = sprintf('%.2f',event.Value);
            app.updateLFOPlot();
            
        end

        % Value changed function: DepthKnob
        function DepthKnobValueChanged(app, event)
            app.lfo_depth = app.DepthKnob.Value;
            app.applyDSP();
            
        end

        % Button pushed function: LoadFileButton
        function LoadFileButtonPushed(app, event)
            [file, path] = uigetfile({'*.wav;*.mp3;*.flac','Audio Files (*.wav, *.mp3, *.flac)'});

            % if user click cancel
            if isequal(file,0)
                return;
            end

            % load and store to memory the file
            fullFileName = fullfile(path,file);
            [app.AudioData, app.Fs] = audioread(fullFileName);
            app.SampleRateSlider.Value = app.Fs;
            app.SampleRateEditField.Value = app.Fs;
            
            % stereo to mono convertion
            if size(app.AudioData, 2) > 1
                app.AudioData = mean(app.AudioData,2);
            end
            
            % init DSP Memory
            app.ReversedData = flipud(app.AudioData);
            app.b_coef_HPF = 1; app.a_coef_HPF = 1; app.filterState_HPF = [];
            app.b_coef_LPF = 1; app.a_coef_LPF = 1; app.filterState_LPF = [];
            app.lfoPhase = 0;

            % init the player
            app.IsPlaying = false;
            app.CurrentSample = 1;
            if ~isempty(app.DeviceWriter)
                release(app.DeviceWriter);   % release the last audio inteface
            end

            app.createAudioDeviceWriter();
            app.PlayButton.Text = 'Play';

            
            % calculate and display the timer
            totalSecs = length(app.AudioData) / app.Fs;
            tmins = floor(totalSecs / 60);
            tsecs = floor(mod(totalSecs, 60));
            app.TimerLabel.Text = sprintf('00:00 / %02d:%02d', tmins, tsecs);

            windowLength = 1024; overlap = 512; nfft = 1024;
            [S_orig, ~, ~] = spectrogram(app.AudioData,windowLength,overlap,nfft,app.Fs);
            app.MaxRefDB = max(10 * log10(abs(S_orig(:)) + eps));

            app.ProcessedData = []; 
            app.MaxRefDB = 0;             
            app.b_coef_HPF = 1; app.a_coef_HPF = 1;   
            app.b_coef_LPF = 1; app.a_coef_LPF = 1;
            app.applyDSP(); 
           
        end

        % Button pushed function: PlayButton
        function PlayButtonPushed(app, event)
            if isempty(app.ProcessedData)
                return;
            end

            % Toggle
            app.IsPlaying = ~app.IsPlaying;
            
            if app.IsPlaying
                app.PlayButton.Text = 'Pause';
                
                % init audio interface
                if ~isempty(app.DeviceWriter)
                    release(app.DeviceWriter);
                end
                app.createAudioDeviceWriter();

                totalSamples = length(app.ProcessedData);
                
                % audio streaming engine
                while isvalid(app) && app.IsPlaying && app.CurrentSample <= totalSamples
                    % fetch 1024 samples from memory
                    endIdx = min(app.CurrentSample + 1023, totalSamples);
                    chunk = app.processLiveChunk(app.CurrentSample,endIdx);

                    % throw chunks to speakers
                    app.DeviceWriter(chunk);
                    app.CurrentSample = endIdx + 1;

                    % update Red Line once 3 blocks
                    if mod(app.CurrentSample, 3072) < 1024
                        currentTime = max(0,(app.CurrentSample / app.Fs) - 0.15);
                        
                        if isgraphics(app.RedLine)
                            app.RedLine.Value = currentTime;
                        end

                        totalSecs = totalSamples / app.Fs;
                        app.TimerLabel.Text = sprintf('%02d:%02d / %02d:%02d', ...
                            floor(currentTime/60), floor(mod(currentTime,60)), ...
                            floor(totalSecs/60), floor(mod(totalSecs,60)));
                    end
                    
                    % to allow interface react
                    drawnow limitrate;
                end

                % init when the song ends
                if isvalid(app) && app.CurrentSample >= totalSamples
                    if app.CurrentSample >= totalSamples
                        app.IsPlaying = false;
                        app.PlayButton.Text = 'Play';
                        app.CurrentSample = 1;
                        if isgraphics(app.RedLine)
                            app.RedLine.Value = 0;
                        end
                    end
                end
                
            else 
                app.PlayButton.Text = 'Play';

            end
        end

        % Value changed function: SampleRateEditField
        function SampleRateEditFieldValueChanged(app, event)
            val = max(1000, min(96000,event.Value));
            app.Fs = val;
            app.SampleRateEditField.Value = val;
            app.SampleRateSlider.Value = val;
            if ~isempty(app.DeviceWriter)
                release(app.DeviceWriter);
                app.DeviceWriter = audioDeviceWriter('SampleRate',app.Fs,'SupportVariableSizeInput',true,'BufferSize',1024);
            end
            app.applyDSP();
            
        end
    end

    % Component initialization
    methods (Access = private)

        % Create UIFigure and components
        function createComponents(app)

            % Create UIFigure and hide until all components are created
            app.UIFigure = uifigure('Visible', 'off');
            app.UIFigure.Position = [100 100 1146 655];
            app.UIFigure.Name = 'MATLAB App';

            % Create GridLayout
            app.GridLayout = uigridlayout(app.UIFigure);
            app.GridLayout.ColumnWidth = {'1x', '3x'};
            app.GridLayout.RowHeight = {'1x', '1x', '1.5x', '3x'};
            app.GridLayout.ColumnSpacing = 1;
            app.GridLayout.RowSpacing = 0.666666666666666;
            app.GridLayout.Padding = [1 0.666666666666666 1 0.666666666666666];

            % Create UIAxesSpectrogram
            app.UIAxesSpectrogram = uiaxes(app.GridLayout);
            title(app.UIAxesSpectrogram, 'Title')
            xlabel(app.UIAxesSpectrogram, 'X')
            ylabel(app.UIAxesSpectrogram, 'Y')
            zlabel(app.UIAxesSpectrogram, 'Z')
            app.UIAxesSpectrogram.Layout.Row = 4;
            app.UIAxesSpectrogram.Layout.Column = 2;

            % Create UIAxesTimeDomain
            app.UIAxesTimeDomain = uiaxes(app.GridLayout);
            title(app.UIAxesTimeDomain, 'Title')
            xlabel(app.UIAxesTimeDomain, 'X')
            ylabel(app.UIAxesTimeDomain, 'Y')
            zlabel(app.UIAxesTimeDomain, 'Z')
            app.UIAxesTimeDomain.Layout.Row = [1 3];
            app.UIAxesTimeDomain.Layout.Column = 2;

            % Create Panel
            app.Panel = uipanel(app.GridLayout);
            app.Panel.Layout.Row = 1;
            app.Panel.Layout.Column = 1;

            % Create LoadFileButton
            app.LoadFileButton = uibutton(app.Panel, 'push');
            app.LoadFileButton.ButtonPushedFcn = createCallbackFcn(app, @LoadFileButtonPushed, true);
            app.LoadFileButton.Position = [5 69 67 23];
            app.LoadFileButton.Text = 'Load File';

            % Create PlayButton
            app.PlayButton = uibutton(app.Panel, 'push');
            app.PlayButton.ButtonPushedFcn = createCallbackFcn(app, @PlayButtonPushed, true);
            app.PlayButton.Position = [1 39 102 23];
            app.PlayButton.Text = 'Play';

            % Create SampleRateSliderLabel
            app.SampleRateSliderLabel = uilabel(app.Panel);
            app.SampleRateSliderLabel.HorizontalAlignment = 'right';
            app.SampleRateSliderLabel.Position = [169 70 74 22];
            app.SampleRateSliderLabel.Text = 'Sample Rate';

            % Create SampleRateSlider
            app.SampleRateSlider = uislider(app.Panel);
            app.SampleRateSlider.Limits = [1000 96000];
            app.SampleRateSlider.MajorTicks = [1000 48000 96000];
            app.SampleRateSlider.MajorTickLabels = {'1k', '48k', '96k'};
            app.SampleRateSlider.ValueChangedFcn = createCallbackFcn(app, @SampleRateSliderValueChanged, true);
            app.SampleRateSlider.Step = 1000;
            app.SampleRateSlider.Position = [147 59 113 3];
            app.SampleRateSlider.Value = 96000;

            % Create SampleRateEditField
            app.SampleRateEditField = uieditfield(app.Panel, 'numeric');
            app.SampleRateEditField.ValueDisplayFormat = '%.0f';
            app.SampleRateEditField.ValueChangedFcn = createCallbackFcn(app, @SampleRateEditFieldValueChanged, true);
            app.SampleRateEditField.HorizontalAlignment = 'center';
            app.SampleRateEditField.Position = [165 8 69 22];
            app.SampleRateEditField.Value = 96000;

            % Create TimerLabel
            app.TimerLabel = uilabel(app.Panel);
            app.TimerLabel.HorizontalAlignment = 'center';
            app.TimerLabel.FontSize = 14;
            app.TimerLabel.Position = [5 8 98 22];
            app.TimerLabel.Text = '00:00 / 00:00';

            % Create TabGroup
            app.TabGroup = uitabgroup(app.GridLayout);
            app.TabGroup.Layout.Row = [3 4];
            app.TabGroup.Layout.Column = 1;

            % Create FilterTab
            app.FilterTab = uitab(app.TabGroup);
            app.FilterTab.Title = 'Filter';

            % Create GridLayout2
            app.GridLayout2 = uigridlayout(app.FilterTab);
            app.GridLayout2.RowHeight = {'1x', '5x', '3x'};

            % Create UIAxesFilterResponse
            app.UIAxesFilterResponse = uiaxes(app.GridLayout2);
            title(app.UIAxesFilterResponse, 'Title')
            xlabel(app.UIAxesFilterResponse, 'X')
            ylabel(app.UIAxesFilterResponse, 'Y')
            zlabel(app.UIAxesFilterResponse, 'Z')
            app.UIAxesFilterResponse.Layout.Row = 2;
            app.UIAxesFilterResponse.Layout.Column = [1 2];

            % Create Panel_3
            app.Panel_3 = uipanel(app.GridLayout2);
            app.Panel_3.Layout.Row = 1;
            app.Panel_3.Layout.Column = [1 2];

            % Create LPFSwitchLabel
            app.LPFSwitchLabel = uilabel(app.Panel_3);
            app.LPFSwitchLabel.HorizontalAlignment = 'center';
            app.LPFSwitchLabel.Position = [185 10 26 22];
            app.LPFSwitchLabel.Text = 'LPF';

            % Create LPFSwitch
            app.LPFSwitch = uiswitch(app.Panel_3, 'slider');
            app.LPFSwitch.Items = {'', ''};
            app.LPFSwitch.ValueChangedFcn = createCallbackFcn(app, @LPFSwitchValueChanged, true);
            app.LPFSwitch.Position = [212 13 35 17];
            app.LPFSwitch.Value = '';

            % Create LPFLamp
            app.LPFLamp = uilamp(app.Panel_3);
            app.LPFLamp.Position = [158 11 20 20];

            % Create HPFLamp
            app.HPFLamp = uilamp(app.Panel_3);
            app.HPFLamp.Position = [23 11 20 20];

            % Create HPFSwitchLabel
            app.HPFSwitchLabel = uilabel(app.Panel_3);
            app.HPFSwitchLabel.HorizontalAlignment = 'center';
            app.HPFSwitchLabel.Position = [49 10 28 22];
            app.HPFSwitchLabel.Text = 'HPF';

            % Create HPFSwitch
            app.HPFSwitch = uiswitch(app.Panel_3, 'slider');
            app.HPFSwitch.Items = {'', ''};
            app.HPFSwitch.ValueChangedFcn = createCallbackFcn(app, @HPFSwitchValueChanged, true);
            app.HPFSwitch.Position = [77 13 35 17];
            app.HPFSwitch.Value = '';

            % Create Panel_5
            app.Panel_5 = uipanel(app.GridLayout2);
            app.Panel_5.Layout.Row = 3;
            app.Panel_5.Layout.Column = 1;

            % Create HPFCutKnobLabel
            app.HPFCutKnobLabel = uilabel(app.Panel_5);
            app.HPFCutKnobLabel.HorizontalAlignment = 'center';
            app.HPFCutKnobLabel.Position = [36 98 51 22];
            app.HPFCutKnobLabel.Text = 'HPF Cut';

            % Create HPFCutKnob
            app.HPFCutKnob = uiknob(app.Panel_5, 'continuous');
            app.HPFCutKnob.Limits = [1.30102999566398 4.30102999566398];
            app.HPFCutKnob.MajorTicks = [1.30102999566398 2.30102999566398 3.30102999566398 4.30102999566398];
            app.HPFCutKnob.MajorTickLabels = {'20', '', '2k', '20k'};
            app.HPFCutKnob.ValueChangedFcn = createCallbackFcn(app, @HPFCutKnobValueChanged, true);
            app.HPFCutKnob.ValueChangingFcn = createCallbackFcn(app, @HPFCutKnobValueChanging, true);
            app.HPFCutKnob.MinorTicks = [1.69897000433602 2 2.69897000433602 3 3.69897000433602 4];
            app.HPFCutKnob.Position = [37 42 43 43];
            app.HPFCutKnob.Value = 2.47712125471966;

            % Create HPFLabel
            app.HPFLabel = uilabel(app.Panel_5);
            app.HPFLabel.HorizontalAlignment = 'center';
            app.HPFLabel.Position = [27 4 65 22];
            app.HPFLabel.Text = '300';

            % Create Panel_9
            app.Panel_9 = uipanel(app.GridLayout2);
            app.Panel_9.Layout.Row = 3;
            app.Panel_9.Layout.Column = 2;

            % Create LPFCutKnobLabel
            app.LPFCutKnobLabel = uilabel(app.Panel_9);
            app.LPFCutKnobLabel.HorizontalAlignment = 'center';
            app.LPFCutKnobLabel.Position = [45 101 49 22];
            app.LPFCutKnobLabel.Text = 'LPF Cut';

            % Create LPFCutKnob
            app.LPFCutKnob = uiknob(app.Panel_9, 'continuous');
            app.LPFCutKnob.Limits = [1.30102999566398 4.30102999566398];
            app.LPFCutKnob.MajorTicks = [1.30102999566398 2.30102999566398 3.30102999566398 4.30102999566398];
            app.LPFCutKnob.MajorTickLabels = {'20', '', '2k', '20k'};
            app.LPFCutKnob.ValueChangedFcn = createCallbackFcn(app, @LPFCutKnobValueChanged, true);
            app.LPFCutKnob.ValueChangingFcn = createCallbackFcn(app, @LPFCutKnobValueChanging, true);
            app.LPFCutKnob.MinorTicks = [1.69897000433602 2 2.69897000433602 3 3.69897000433602 4];
            app.LPFCutKnob.Position = [45 45 43 43];
            app.LPFCutKnob.Value = 3.90308998699194;

            % Create LPFLabel
            app.LPFLabel = uilabel(app.Panel_9);
            app.LPFLabel.HorizontalAlignment = 'center';
            app.LPFLabel.Position = [35 6 61 22];
            app.LPFLabel.Text = '8000';

            % Create TremoloTab
            app.TremoloTab = uitab(app.TabGroup);
            app.TremoloTab.Title = 'Tremolo';

            % Create GridLayout3
            app.GridLayout3 = uigridlayout(app.TremoloTab);
            app.GridLayout3.RowHeight = {'1x', '5x', '3x'};

            % Create UIAxesTremoloLFO
            app.UIAxesTremoloLFO = uiaxes(app.GridLayout3);
            title(app.UIAxesTremoloLFO, 'Title')
            xlabel(app.UIAxesTremoloLFO, 'X')
            ylabel(app.UIAxesTremoloLFO, 'Y')
            zlabel(app.UIAxesTremoloLFO, 'Z')
            app.UIAxesTremoloLFO.Layout.Row = 2;
            app.UIAxesTremoloLFO.Layout.Column = [1 2];

            % Create Panel_6
            app.Panel_6 = uipanel(app.GridLayout3);
            app.Panel_6.Layout.Row = 1;
            app.Panel_6.Layout.Column = [1 2];

            % Create TremoloLamp
            app.TremoloLamp = uilamp(app.Panel_6);
            app.TremoloLamp.Position = [71 11 20 20];

            % Create TremoloSwitchLabel
            app.TremoloSwitchLabel = uilabel(app.Panel_6);
            app.TremoloSwitchLabel.HorizontalAlignment = 'center';
            app.TremoloSwitchLabel.Position = [101 10 48 22];
            app.TremoloSwitchLabel.Text = 'Tremolo';

            % Create TremoloSwitch
            app.TremoloSwitch = uiswitch(app.Panel_6, 'slider');
            app.TremoloSwitch.Items = {'', ''};
            app.TremoloSwitch.ValueChangedFcn = createCallbackFcn(app, @TremoloSwitchValueChanged, true);
            app.TremoloSwitch.Position = [157 13 35 17];
            app.TremoloSwitch.Value = '';

            % Create Panel_10
            app.Panel_10 = uipanel(app.GridLayout3);
            app.Panel_10.Layout.Row = 3;
            app.Panel_10.Layout.Column = 1;

            % Create RateLabel
            app.RateLabel = uilabel(app.Panel_10);
            app.RateLabel.HorizontalAlignment = 'center';
            app.RateLabel.Position = [27 5 65 21];
            app.RateLabel.Text = '0';

            % Create RateKnobLabel
            app.RateKnobLabel = uilabel(app.Panel_10);
            app.RateKnobLabel.HorizontalAlignment = 'center';
            app.RateKnobLabel.Position = [47 98 30 22];
            app.RateKnobLabel.Text = 'Rate';

            % Create RateKnob
            app.RateKnob = uiknob(app.Panel_10, 'continuous');
            app.RateKnob.Limits = [0 15];
            app.RateKnob.MajorTicks = [0.1 7.5 15];
            app.RateKnob.MajorTickLabels = {'0.1', '7.5', '15'};
            app.RateKnob.ValueChangedFcn = createCallbackFcn(app, @RateKnobValueChanged, true);
            app.RateKnob.ValueChangingFcn = createCallbackFcn(app, @RateKnobValueChanging, true);
            app.RateKnob.MinorTicks = [2.5 5 10 12.5];
            app.RateKnob.Position = [37 42 43 43];
            app.RateKnob.Value = 5;

            % Create Panel_11
            app.Panel_11 = uipanel(app.GridLayout3);
            app.Panel_11.Layout.Row = 3;
            app.Panel_11.Layout.Column = 2;

            % Create DepthLabel
            app.DepthLabel = uilabel(app.Panel_11);
            app.DepthLabel.HorizontalAlignment = 'center';
            app.DepthLabel.Position = [33 7 65 21];
            app.DepthLabel.Text = '0';

            % Create DepthKnobLabel
            app.DepthKnobLabel = uilabel(app.Panel_11);
            app.DepthKnobLabel.HorizontalAlignment = 'center';
            app.DepthKnobLabel.Position = [51 101 37 22];
            app.DepthKnobLabel.Text = 'Depth';

            % Create DepthKnob
            app.DepthKnob = uiknob(app.Panel_11, 'continuous');
            app.DepthKnob.Limits = [0 1];
            app.DepthKnob.MajorTicks = [0 0.5 1];
            app.DepthKnob.MajorTickLabels = {'0', '0.5', '1'};
            app.DepthKnob.ValueChangedFcn = createCallbackFcn(app, @DepthKnobValueChanged, true);
            app.DepthKnob.ValueChangingFcn = createCallbackFcn(app, @DepthKnobValueChanging, true);
            app.DepthKnob.MinorTicks = [0.25 0.75];
            app.DepthKnob.Position = [45 45 43 43];
            app.DepthKnob.Value = 0.8;

            % Create Panel_2
            app.Panel_2 = uipanel(app.GridLayout);
            app.Panel_2.Layout.Row = 2;
            app.Panel_2.Layout.Column = 1;

            % Create ReverseSwitch
            app.ReverseSwitch = uiswitch(app.Panel_2, 'slider');
            app.ReverseSwitch.Items = {'', ''};
            app.ReverseSwitch.ValueChangedFcn = createCallbackFcn(app, @ReverseSwitchValueChanged, true);
            app.ReverseSwitch.Position = [215 43 45 20];
            app.ReverseSwitch.Value = '';

            % Create ReversedLampLabel
            app.ReversedLampLabel = uilabel(app.Panel_2);
            app.ReversedLampLabel.HorizontalAlignment = 'right';
            app.ReversedLampLabel.Position = [195 67 56 22];
            app.ReversedLampLabel.Text = 'Reversed';

            % Create ReverseLamp
            app.ReverseLamp = uilamp(app.Panel_2);
            app.ReverseLamp.Position = [259 68 20 20];

            % Create VolumeKnobLabel
            app.VolumeKnobLabel = uilabel(app.Panel_2);
            app.VolumeKnobLabel.HorizontalAlignment = 'center';
            app.VolumeKnobLabel.Position = [27 67 45 22];
            app.VolumeKnobLabel.Text = 'Volume';

            % Create VolumeKnob
            app.VolumeKnob = uiknob(app.Panel_2, 'continuous');
            app.VolumeKnob.MajorTickLabels = {'0', '20', '40', '60', '80', '100'};
            app.VolumeKnob.ValueChangedFcn = createCallbackFcn(app, @VolumeKnobValueChanged, true);
            app.VolumeKnob.ValueChangingFcn = createCallbackFcn(app, @VolumeKnobValueChanging, true);
            app.VolumeKnob.Position = [107 28 47 47];

            % Create VolumeLabel
            app.VolumeLabel = uilabel(app.Panel_2);
            app.VolumeLabel.HorizontalAlignment = 'center';
            app.VolumeLabel.Position = [28 42 49 22];
            app.VolumeLabel.Text = '0';

            % Show the figure after all components are created
            app.UIFigure.Visible = 'on';
        end
    end

    % App creation and deletion
    methods (Access = public)

        % Construct app
        function app = audioPlayer_exported

            % Create UIFigure and components
            createComponents(app)

            % Register the app with App Designer
            registerApp(app, app.UIFigure)

            % Execute the startup function
            runStartupFcn(app, @startupFcn)

            if nargout == 0
                clear app
            end
        end

        % Code that executes before app deletion
        function delete(app)

            % Delete UIFigure when app is deleted
            delete(app.UIFigure)
        end
    end
end