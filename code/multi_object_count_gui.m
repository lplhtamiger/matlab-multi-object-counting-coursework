function multi_object_count_gui
clc; close all;
%% ======================== 1. 创建主界面 =============================
fig = figure('Name','多目标物品自动计数与位置标注系统', ...
    'NumberTitle','off', ...
    'Position',[60 40 1450 780], ...
    'Color',[0.94 0.94 0.94]);

% 全局变量，用于在各个回调函数之间共享数据
img = [];        % 原始输入图像
resultImg = [];  % 最终识别结果图，用于保存

%% ======================== 2. 创建按钮控件 =============================
% 加载图片按钮
uicontrol('Style','pushbutton','String','加载图片', ...
    'Position',[40 720 120 38], ...
    'FontSize',11, ...
    'Callback',@loadImage);

% 开始识别按钮
uicontrol('Style','pushbutton','String','开始识别', ...
    'Position',[180 720 120 38], ...
    'FontSize',11, ...
    'Callback',@processImage);

% 保存识别结果按钮
uicontrol('Style','pushbutton','String','保存结果', ...
    'Position',[320 720 120 38], ...
    'FontSize',11, ...
    'Callback',@saveResult);

% 清空界面按钮
uicontrol('Style','pushbutton','String','清空', ...
    'Position',[460 720 120 38], ...
    'FontSize',11, ...
    'Callback',@clearAll);

%% ======================== 3. 创建图像显示区域 =========================
% 采用 2 行 3 列布局，依次展示图像处理的主要过程。
ax1 = axes('Parent',fig,'Units','pixels','Position',[40 430 280 240]);
title(ax1,'原图'); axis(ax1,'off');

ax2 = axes('Parent',fig,'Units','pixels','Position',[350 430 280 240]);
title(ax2,'灰度图'); axis(ax2,'off');

ax3 = axes('Parent',fig,'Units','pixels','Position',[660 430 280 240]);
title(ax3,'去噪图'); axis(ax3,'off');

ax4 = axes('Parent',fig,'Units','pixels','Position',[40 100 280 240]);
title(ax4,'二值化图'); axis(ax4,'off');

ax5 = axes('Parent',fig,'Units','pixels','Position',[350 100 280 240]);
title(ax5,'形态学处理'); axis(ax5,'off');

ax6 = axes('Parent',fig,'Units','pixels','Position',[660 100 280 240]);
title(ax6,'识别结果'); axis(ax6,'off');

%% ======================== 4. 创建结果输出区域 =========================
uicontrol('Style','text', ...
    'String','检测结果与坐标输出', ...
    'Position',[1020 665 300 30], ...
    'FontSize',13, ...
    'FontWeight','bold', ...
    'BackgroundColor',[0.94 0.94 0.94]);

% 使用 listbox 显示目标数量、中心坐标和面积信息，避免文字显示不全。
resultList = uicontrol('Style','listbox', ...
    'Position',[990 100 380 560], ...
    'FontSize',11, ...
    'BackgroundColor','white', ...
    'String',{'等待识别结果...'});

%% ======================== 5. 加载图片回调函数 =========================
    function loadImage(~,~)
        % 弹出文件选择框，选择待处理图像
        [file,path] = uigetfile({'*.jpg;*.png;*.bmp;*.jpeg','图像文件'});
        if isequal(file,0)
            return;
        end

        % 读取图像并显示原图
        img = imread(fullfile(path,file));

        axes(ax1);
        imshow(img);
        title('原图');
        axis off;

        % 更新右侧提示信息
        set(resultList,'String',{'图片加载成功','请点击“开始识别”'});
    end

%% ======================== 6. 图像处理与目标识别 =======================
    function processImage(~,~)
        % 若未加载图片，则提示用户先加载图片
        if isempty(img)
            msgbox('请先加载图片！','提示','warn');
            return;
        end

        %% 6.1 灰度化处理
        % 彩色图像包含 R、G、B 三个通道，不便于直接阈值分割。
        % 因此先将彩色图像转换为单通道灰度图像。
        if size(img,3) == 3
            grayImg = rgb2gray(img);
        else
            grayImg = img;
        end

        axes(ax2);
        imshow(grayImg);
        title('灰度图');
        axis off;

        %% 6.2 中值滤波去噪
        % 中值滤波能够有效抑制椒盐噪声和局部细小干扰，
        % 同时较好地保持物体边缘信息。
        grayFilter = medfilt2(grayImg,[3 3]);

        axes(ax3);
        imshow(grayFilter);
        title('去噪图');
        axis off;

        %% 6.3 自适应二值化
        % 自适应阈值能够根据局部亮度变化进行分割，
        % 相比固定阈值更适合普通手机拍摄图像。
        bwImg = imbinarize(grayFilter,'adaptive', ...
            'ForegroundPolarity','dark', ...
            'Sensitivity',0.45);

        % 判断前景和背景是否反转，保证目标区域为白色、背景为黑色。
        if sum(bwImg(:)) > numel(bwImg)/2
            bwImg = ~bwImg;
        end

        axes(ax4);
        imshow(bwImg);
        title('二值化图');
        axis off;

        %% 6.4 形态学处理
        % bwareaopen：删除面积过小的噪声区域；
        % imclose：闭运算，用于连接目标边缘中的小断裂；
        % imfill：填充目标内部孔洞，便于后续连通域分析。
        bwClean = bwareaopen(bwImg,150);
        bwClean = imclose(bwClean,strel('disk',5));
        bwClean = imfill(bwClean,'holes');

        axes(ax5);
        imshow(bwClean);
        title('形态学处理');
        axis off;

        %% 6.5 连通域特征提取
        % regionprops 用于提取每个连通区域的外接矩形、中心点和面积。
        stats = regionprops(bwClean,'BoundingBox','Centroid','Area');

        imgArea = size(grayImg,1) * size(grayImg,2);
        validStats = [];

        % 根据面积阈值筛除噪声和过大的异常区域。
        % 下限 300：去除细小噪声；
        % 上限 imgArea*0.25：防止大面积背景或阴影被误认为目标。
        for i = 1:length(stats)
            area = stats(i).Area;
            if area > 300 && area < imgArea * 0.25
                validStats = [validStats; stats(i)]; %#ok<AGROW>
            end
        end

        % 目标数量即有效连通区域数量
        count = length(validStats);

        %% 6.6 结果显示与坐标输出
        axes(ax6);
        imshow(img);
        title(['识别结果：共检测到 ',num2str(count),' 个目标']);
        axis off;
        hold on;

        % 右侧列表输出内容
        outputText = cell(count + 2, 1);
        outputText{1} = ['共检测到目标数量：', num2str(count)];
        outputText{2} = '--------------------------------';

        % 对每个目标绘制外接矩形、中心点和编号
        for i = 1:count
            box = validStats(i).BoundingBox;
            center = validStats(i).Centroid;
            area = validStats(i).Area;

            % 绘制红色外接矩形
            rectangle('Position',box,'EdgeColor','r','LineWidth',2);

            % 绘制绿色中心点
            plot(center(1),center(2),'g+','MarkerSize',10,'LineWidth',2);

            % 在目标框左上方标注编号
            text(box(1),box(2)-8,num2str(i), ...
                'Color','y', ...
                'FontSize',12, ...
                'FontWeight','bold');

            % 输出目标中心坐标和面积
            outputText{i+2} = sprintf( ...
                '目标%d：中心坐标 X=%.1f，Y=%.1f，面积=%.0f', ...
                i,center(1),center(2),area);
        end

        hold off;
        set(resultList,'String',outputText);

        % 获取最终识别结果图，用于保存
        frame = getframe(ax6);
        resultImg = frame.cdata;
    end

%% ======================== 7. 保存结果回调函数 =========================
    function saveResult(~,~)
        % 若尚未识别，则不允许保存
        if isempty(resultImg)
            msgbox('请先完成识别！','提示','warn');
            return;
        end

        % 弹出保存对话框
        [file,path] = uiputfile({'*.png','PNG图像'},'保存识别结果','result.png');
        if isequal(file,0)
            return;
        end

        % 保存识别结果图
        imwrite(resultImg,fullfile(path,file));
        msgbox('结果保存成功！','提示');
    end

%% ======================== 8. 清空界面回调函数 =========================
    function clearAll(~,~)
        % 清空数据变量
        img = [];
        resultImg = [];

        % 清空所有图像显示区域，并保持坐标轴关闭
        cla(ax1); title(ax1,'原图'); axis(ax1,'off');
        cla(ax2); title(ax2,'灰度图'); axis(ax2,'off');
        cla(ax3); title(ax3,'去噪图'); axis(ax3,'off');
        cla(ax4); title(ax4,'二值化图'); axis(ax4,'off');
        cla(ax5); title(ax5,'形态学处理'); axis(ax5,'off');
        cla(ax6); title(ax6,'识别结果'); axis(ax6,'off');

        % 恢复结果提示
        set(resultList,'String',{'等待识别结果...'});
    end

end
