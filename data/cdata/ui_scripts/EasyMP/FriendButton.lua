-- list row button for the EasyMP friends menu, based on ModSelectButton

local function PostLoadFunc(buttonElement, controllerIndex, controller)
    assert(buttonElement.GenericButton)

    buttonElement.GenericButton:addEventHandler("button_action", function(clickedElement, eventArgs)
        local dataSource = buttonElement:GetDataSource()
        dataSource.buttonOnClickFunction(clickedElement, eventArgs)
    end)

    buttonElement.GenericButton:addEventHandler("button_over", function(hoveredElement, eventArgs)
        local dataSource = buttonElement:GetDataSource()
        dataSource.buttonOnHoverFunction(hoveredElement, eventArgs)
    end)

    buttonElement.GenericButton:addEventHandler("button_up", function(unhoveredElement, eventArgs)
        local dataSource = buttonElement:GetDataSource()
        dataSource.buttonOnHoverFunction(unhoveredElement, eventArgs)
    end)

    buttonElement:registerEventHandler("grid_anim", function(element, event)
        element:SetAlpha(event.value)
    end)

    buttonElement:SubscribeToDataSourceThroughElement(buttonElement, nil, function()
    end)
end

function EasyMPFriendButton(menu, controller)
    local EasyMPFriendButton = LUI.UIButton.new()
    EasyMPFriendButton:SetAnchorsAndPosition(0, 1, 0, 1, 0, 500 * _1080p, 0, 30 * _1080p)
    EasyMPFriendButton.id = "EasyMPFriendButton"
    EasyMPFriendButton._animationSets = {}
    EasyMPFriendButton._sequences = {}

    local controllerIndex = controller and controller.controllerIndex
    if not controllerIndex and not Engine.InFrontend() then
        controllerIndex = EasyMPFriendButton:getRootController()
    end
    assert(controllerIndex)

    local GenericButton = nil

    GenericButton = MenuBuilder.BuildRegisteredType("GenericButton", {
        controllerIndex = controllerIndex
    })
    GenericButton.id = "GenericButton"
    GenericButton:SetAlpha(0, 0)
    GenericButton:SetAnchorsAndPosition(0, 1, 0, 0, 0, _1080p * 500, 0, 0)

    GenericButton:SubscribeToModelThroughElement(EasyMPFriendButton, "buttonLabel", function()
        local dataSource = EasyMPFriendButton:GetDataSource()
        local buttonLabel = dataSource.buttonLabel:GetValue(controllerIndex)
        if buttonLabel ~= nil then
            GenericButton.Text:setText(LocalizeString(buttonLabel), 0)
        end
    end)

    EasyMPFriendButton:addElement(GenericButton)
    EasyMPFriendButton.GenericButton = GenericButton

    local GenericListArrowButtonBackground = nil

    GenericListArrowButtonBackground = MenuBuilder.BuildRegisteredType("GenericListArrowButtonBackground", {
        controllerIndex = controllerIndex
    })
    GenericListArrowButtonBackground.id = "GenericListButtonBackground"
    GenericListArrowButtonBackground:SetAnchorsAndPosition(0, 0, 0, 0, 0, 0, 0, 0)

    EasyMPFriendButton:addElement(GenericListArrowButtonBackground)
    EasyMPFriendButton.GenericListButtonBackground = GenericListArrowButtonBackground

    local Text = nil

    Text = LUI.UIStyledText.new()
    Text.id = "Text"
    Text:SetRGBFromInt(14277081, 0)
    Text:SetFontSize(22 * _1080p)
    Text:SetFont(FONTS.GetFont(FONTS.MainMedium.File))
    Text:SetAlignment(LUI.Alignment.Left)
    Text:SetStartupDelay(2000)
    Text:SetLineHoldTime(400)
    Text:SetAnimMoveTime(300)
    Text:SetEndDelay(1500)
    Text:SetCrossfadeTime(750)
    Text:SetAutoScrollStyle(LUI.UIStyledText.AutoScrollStyle.ScrollH)
    Text:SetMaxVisibleLines(1)
    Text:SetOutlineRGBFromInt(0, 0)
    Text:SetAnchorsAndPosition(0, 0, 0.5, 0.5, _1080p * 44, _1080p * -41, _1080p * -11, _1080p * 11)

    EasyMPFriendButton:addElement(Text)
    EasyMPFriendButton.Text = Text

    -- colored status square (tintable "white" material), shown for friend rows
    local StatusDot = nil
    pcall(function()
        StatusDot = LUI.UIImage.new()
        StatusDot.id = "StatusDot"
        StatusDot:setImage(RegisterMaterial("white"), 0)
        StatusDot:SetAlpha(0, 0)
        StatusDot:SetAnchorsAndPosition(0, 0, 0.5, 0.5, _1080p * 16, _1080p * 32, _1080p * -8, _1080p * 8)
        EasyMPFriendButton:addElement(StatusDot)
        EasyMPFriendButton.StatusDot = StatusDot
    end)

    Text:SubscribeToModelThroughElement(EasyMPFriendButton, "buttonLabel", function()
        local dataSource = EasyMPFriendButton:GetDataSource()
        local buttonLabel = dataSource.buttonLabel:GetValue(controllerIndex)
        if buttonLabel == nil then
            return
        end

        local display = buttonLabel
        local color = nil
        if string.find(buttonLabel, "%[EN PARTIE%]") then
            color = 0x3AC36B       -- green
            display = string.gsub(buttonLabel, "%[EN PARTIE%] ", "")
        elseif string.find(buttonLabel, "%[EN LIGNE%]") then
            color = 0xE6C341       -- amber
            display = string.gsub(buttonLabel, "%[EN LIGNE%] ", "")
        elseif string.find(buttonLabel, "%[HORS LIGNE%]") then
            color = 0xA05052       -- muted red
            display = string.gsub(buttonLabel, "%[HORS LIGNE%] ", "")
        end

        Text:setText(LocalizeString(display), 0)

        if StatusDot then
            pcall(function()
                if color then
                    StatusDot:SetRGBFromInt(color, 0)
                    StatusDot:SetAlpha(1, 0)
                else
                    StatusDot:SetAlpha(0, 0)
                end
            end)
        end
    end)

    EasyMPFriendButton._animationSets.DefaultAnimationSet = function()
        EasyMPFriendButton._sequences.DefaultSequence = function()
        end

        Text:RegisterAnimationSequence("ButtonOver", {{function()
            return EasyMPFriendButton.Text:SetRGBFromInt(0, 0)
        end}, {function()
            return EasyMPFriendButton.Text:SetAlpha(1, 0)
        end}})

        EasyMPFriendButton._sequences.ButtonOver = function()
            Text:AnimateSequence("ButtonOver")
        end

        Text:RegisterAnimationSequence("ButtonUp", {{function()
            return EasyMPFriendButton.Text:SetRGBFromInt(14277081, 0)
        end}})

        EasyMPFriendButton._sequences.ButtonUp = function()
            Text:AnimateSequence("ButtonUp")
        end

        Text:RegisterAnimationSequence("ButtonOverDisabled", {{function()
            return EasyMPFriendButton.Text:SetRGBFromInt(0, 0)
        end}, {function()
            return EasyMPFriendButton.Text:SetAlpha(1, 0)
        end}})

        EasyMPFriendButton._sequences.ButtonOverDisabled = function()
            Text:AnimateSequence("ButtonOverDisabled")
        end

        Text:RegisterAnimationSequence("ButtonUpDisabled", {{function()
            return EasyMPFriendButton.Text:SetRGBFromInt(14277081, 0)
        end}})

        EasyMPFriendButton._sequences.ButtonUpDisabled = function()
            Text:AnimateSequence("ButtonUpDisabled")
        end
    end

    EasyMPFriendButton._animationSets.DefaultAnimationSet()
    PostLoadFunc(EasyMPFriendButton, controllerIndex, controller)
    return EasyMPFriendButton
end

MenuBuilder.registerType("EasyMPFriendButton", EasyMPFriendButton)
