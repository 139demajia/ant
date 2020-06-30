--this file is for create autocomplete symbols,not for running

function imgui.create() end
function imgui.destroy() end
function imgui.keymap() end
function imgui.begin_frame() end
function imgui.end_frame() end
function imgui.keyboard() end
function imgui.input_char() end
function imgui.mouse_move() end
function imgui.input_char() end
function imgui.mouse_click() end
function imgui.resize() end
function imgui.viewid() end
function imgui.program() end
function imgui.ime_handle() end
function imgui.IO() end
function imgui.setDockEnable(boolean) end
function imgui.showDockSpace() end

function widget.Button(label,w,h) end
function widget.SmallButton() end
function widget.InvisibleButton() end
function widget.ArrowButton() end
--@return change,new_value
function widget.Checkbox(field,value) end
function widget.RadioButton(name,selected) end
function widget.ProgressBar() end
function widget.Bullet() end
function widget.DragFloat() end
function widget.DragInt() end
function widget.SliderFloat() end
function widget.SliderInt() end
function widget.SliderAngle() end
function widget.VSliderFloat() end
function widget.VSliderInt() end
function widget.ColorEdit() end
function widget.ColorPicker() end
function widget.ColorButton() end
function widget.InputText() end
--@return value change
function widget.InputFloat(title,{flag = flags.InputText,val1,...}) end
--@return value change
function widget.InputInt(title,{flag = flags.InputText, val1,...}) end
function widget.Text() end
function widget.TextDisabled() end
function widget.TextWrapped() end
function widget.LabelText() end
function widget.BulletText() end
function widget.BeginCombo() end
function widget.EndCombo() end
--widget.Selectable(name,{[1]=select_name,item_flags=?,width=?,height=?},disable)
--@return pressed
function widget.Selectable(name,selected,x,y,flags,disable) end
function widget.TreeNode(name,flags) end
function widget.TreePush(name) end
--@desc:call if TreePush or TreeNode Opened
function widget.TreePop() end
--@param title:string
--@return bool
function widget.CollapsingHeader(title) end
function widget.SetNextItemOpen(is_open,ImGuiCond) end
function widget.PlotLines() end
function widget.PlotHistogram() end
function widget.BeginTooltip() end
function widget.EndTooltip() end
function widget.SetTooltip() end
function widget.BeginMainMenuBar() end
function widget.EndMainMenuBar() end
function widget.BeginMenuBar() end
function widget.EndMenuBar() end
function widget.BeginMenu() end
function widget.EndMenu() end
function widget.MenuItem() end
function widget.BeginListBox() end
function widget.BeginListBoxN() end
function widget.EndListBox() end
function widget.ListBox() end
function widget.Image() end
function widget.ImageButton() end
--return bool
function widget.BeginDragDropSource(ImGuiDragDropFlags flag) end
function widget.EndDragDropSource() end
--ImGuiCond = "A/a"=Appearing,"O/o"=Once,"F/f"=FirstUseEver,default = "Always"
--return bool
function widget.SetDragDropPayload(string type,string data,opt ImGuiCond cond) end
--return bool
function widget.BeginDragDropTarget() end
function widget.EndDragDropTarget() end
--data or nil = AcceptDragDropPayload( type,ImGuiDragDropFlags );
--change = AcceptDragDropPayload( { type=[in],flags==[in],data=[out],isPreview=[out],isDelivery=[out] } );
function widget.AcceptDragDropPayload(string type,ImGuiDragDropFlags f) end
function widget.PushTextWrapPos(float pos) end
function widget.PopTextWrapPos() end

function cursor.Separator() end
function cursor.SameLine() end
function cursor.NewLine() end
function cursor.Spacing() end
function cursor.Dummy() end
function cursor.Indent() end
function cursor.Unindent() end
function cursor.BeginGroup() end
function cursor.EndGroup() end
function cursor.GetCursorPos() end
function cursor.SetCursorPos() end
function cursor.GetCursorStartPos() end
function cursor.GetCursorScreenPos() end
function cursor.SetCursorScreenPos() end
function cursor.AlignTextToFramePadding() end
function cursor.GetTextLineHeight() end
function cursor.GetTextLineHeightWithSpacing() end
function cursor.GetFrameHeight() end
function cursor.GetFrameHeightWithSpacing() end
function cursor.TreeAdvanceToLabelPos() end
function cursor.GetTreeNodeToLabelSpacing() end
function cursor.Columns(num,strid,withborder) end
function cursor.NextColumn() end
function cursor.GetColumnIndex() end --start from 1
--index = 0 or nil:get current column offset
--return float offset
function cursor.GetColumnOffset(int index) end
-- index = 0:set current column
function cursor.SetColumnOffset(int index,float offset) end
function cursor.SetNextItemWidth() end
function cursor.SetMouseCursor( cursor = enum.MouseCursor.Arrow ) end

--@return
--  opening:false if window is collapsed;
--  closebtn_change:return false if clicked;
function windows.Begin(title_id,flag) end
function windows.End() end
--@param strid
--@param w,h:default 0
--@param has_border:default false
--@param flags:default 0
--@return opening
function windows.BeginChild(strid,w,h,has_border,flags) end --return change
function windows.EndChild() end
function windows.BeginTabBar() end
function windows.EndTabBar() end
function windows.BeginTabItem() end
function windows.EndTabItem() end
function windows.SetTabItemClosed() end
function windows.OpenPopup() end
function windows.BeginPopup() end
function windows.BeginPopupContextItem(strid,boolean) end --return open
function windows.BeginPopupContextWindow() end
function windows.BeginPopupContextVoid() end
function windows.BeginPopupModal() end
function windows.EndPopup() end
function windows.OpenPopupContextItem() end
function windows.IsPopupOpen() end
function windows.CloseCurrentPopup() end
function windows.IsWindowAppearing() end
function windows.IsWindowCollapsed() end
function windows.IsWindowFocused() end
function windows.IsWindowHovered() end
function windows.GetWindowPos() end
function windows.GetWindowSize() end
function windows.GetScrollX() end
function windows.GetScrollY() end
function windows.GetScrollMaxX() end
function windows.GetScrollMaxY() end
function windows.SetScrollX() end
function windows.SetScrollY() end
function windows.SetScrollHereY() end
function windows.SetScrollFromPosY() end
function windows.SetNextWindowPos() end
function windows.SetNextWindowSize(x,y,ImGuiCond) end
function windows.SetNextWindowSizeConstraints() end
function windows.SetNextWindowContentSize() end
function windows.SetNextWindowCollapsed() end
function windows.SetNextWindowFocus(nil) end
function windows.SetNextWindowBgAlpha() end
function windows.GetContentRegionMax() end
function windows.GetContentRegionAvail() end
function windows.GetWindowContentRegionMin() end
function windows.GetWindowContentRegionMax() end
function windows.GetWindowContentRegionWidth() end
--co1 0~1
function windows.PushStyleColor(enum.StyleCol.XXX,col_r,col_g,col_b,col_a) end
function windows.PopStyleColor(num) end
function windows.PushStyleVar(enum.StyleVal.XXX,v1,...) end
function windows.PopStyleVar(num) end
function windows.SetWindowFontScale() end

function util.SetColorEditOptions() end
function util.PushClipRect() end
function util.PopClipRect() end
function util.SetItemDefaultFocus() end
function util.SetKeyboardFocusHere() end
function util.IsItemHovered() end
function util.IsItemActive() end
function util.IsItemFocused() end
function util.IsItemClicked() end
function util.IsItemVisible() end
function util.IsItemEdited() end
function util.IsItemActivated() end
function util.IsItemDeactivated() end
function util.IsItemDeactivatedAfterEdit() end
function util.IsAnyItemHovered() end
function util.IsAnyItemActive() end
function util.IsAnyItemFocused() end
function util.GetItemRectMin() end
function util.GetItemRectMax() end
function util.GetItemRectSize() end
function util.SetItemAllowOverlap() end
function util.LoadIniSettings() end
function util.SaveIniSettings(clear_want_save_flag) end
function util.CaptureKeyboardFromApp() end
function util.CaptureMouseFromApp() end
function util.IsMouseDoubleClicked() end
--@param id:integer or string
function util.PushID(id)
function util.PopID()
--@param label
--@param *hide_text_after_double_hash:default false;
--@param *wrap_width:default -1.0f
--@return x,y
function util.CalcTextSize(label,hide_text_after_double_hash,wrap_width)
function util.CalcItemWidth()

function flags.ColorEdit.NoAlpha() end
function flags.ColorEdit.NoPicker() end
function flags.ColorEdit.NoOptions() end
function flags.ColorEdit.NoSmallPreview() end
function flags.ColorEdit.NoInputs() end
function flags.ColorEdit.NoTooltip() end
function flags.ColorEdit.NoLabel() end
function flags.ColorEdit.NoSidePreview() end
function flags.ColorEdit.NoDragDrop() end
function flags.ColorEdit.AlphaBar() end
function flags.ColorEdit.AlphaPreview() end
function flags.ColorEdit.AlphaPreviewHalf() end
function flags.ColorEdit.HDR() end
function flags.ColorEdit.DisplayRGB() end
function flags.ColorEdit.DisplayHSV() end
function flags.ColorEdit.DisplayHex() end
function flags.ColorEdit.Uint8() end
function flags.ColorEdit.Float() end
function flags.ColorEdit.PickerHueBar() end
function flags.ColorEdit.PickerHueWheel() end
function flags.ColorEdit.InputRGB() end
function flags.ColorEdit.InputHSV() end

function flags.InputText.CharsDecimal() end
function flags.InputText.CharsHexadecimal() end
function flags.InputText.CharsUppercase() end
function flags.InputText.CharsNoBlank() end
function flags.InputText.AutoSelectAll() end
function flags.InputText.EnterReturnsTrue() end
function flags.InputText.CallbackCompletion() end
function flags.InputText.CallbackHistory() end
function flags.InputText.CallbackCharFilter() end
function flags.InputText.AllowTabInput() end
function flags.InputText.CtrlEnterForNewLine() end
function flags.InputText.NoHorizontalScroll() end
function flags.InputText.AlwaysInsertMode() end
function flags.InputText.ReadOnly() end
function flags.InputText.Password() end
function flags.InputText.NoUndoRedo() end
function flags.InputText.CharsScientific() end
function flags.InputText.CallbackResize() end
function flags.InputText.Multiline() end

function flags.Combo.PopupAlignLeft() end
function flags.Combo.HeightSmall() end
function flags.Combo.HeightRegular() end
function flags.Combo.HeightLarge() end
function flags.Combo.HeightLargest() end
function flags.Combo.NoArrowButton() end
function flags.Combo.NoPreview() end

function flags.Selectable.DontClosePopups() end
function flags.Selectable.SpanAllColumns() end
function flags.Selectable.AllowDoubleClick() end
function flags.Selectable.AllowItemOverlap() end

function flags.TreeNode.Selected() end
function flags.TreeNode.Framed() end
function flags.TreeNode.AllowItemOverlap() end
function flags.TreeNode.NoTreePushOnOpen() end
function flags.TreeNode.NoAutoOpenOnLog() end
function flags.TreeNode.DefaultOpen() end
function flags.TreeNode.OpenOnDoubleClick() end
function flags.TreeNode.OpenOnArrow() end
function flags.TreeNode.Leaf() end
function flags.TreeNode.Bullet() end
function flags.TreeNode.FramePadding() end
function flags.TreeNode.SpanAvailWidth() end
function flags.TreeNode.SpanFullWidth() end
function flags.TreeNode.NavLeftJumpsBackHere() end
function flags.TreeNode.CollapsingHeader() end

function flags.Window.NoTitleBar() end
function flags.Window.NoResize() end
function flags.Window.NoMove() end
function flags.Window.NoScrollbar() end
function flags.Window.NoScrollWithMouse() end
function flags.Window.NoCollapse() end
function flags.Window.AlwaysAutoResize() end
function flags.Window.NoBackground() end
function flags.Window.NoSavedSettings() end
function flags.Window.NoMouseInputs() end
function flags.Window.MenuBar() end
function flags.Window.HorizontalScrollbar() end
function flags.Window.NoFocusOnAppearing() end
function flags.Window.NoBringToFrontOnFocus() end
function flags.Window.AlwaysVerticalScrollbar() end
function flags.Window.AlwaysHorizontalScrollbar() end
function flags.Window.AlwaysUseWindowPadding() end
function flags.Window.NoNavInputs() end
function flags.Window.NoNavFocus() end
function flags.Window.UnsavedDocument() end
function flags.Window.NoNav() end
function flags.Window.NoDecoration() end
function flags.Window.NoInputs() end

function flags.Focused.ChildWindows() end
function flags.Focused.RootWindow() end
function flags.Focused.AnyWindow() end
function flags.Focused.RootAndChildWindows() end

function flags.Hovered.ChildWindows() end
function flags.Hovered.RootWindow() end
function flags.Hovered.AnyWindow() end
function flags.Hovered.AllowWhenBlockedByPopup() end
function flags.Hovered.AllowWhenBlockedByActiveItem() end
function flags.Hovered.AllowWhenOverlapped() end
function flags.Hovered.AllowWhenDisabled() end
function flags.Hovered.RectOnly() end
function flags.Hovered.RootAndChildWindows() end

function flags.TabBar.Reorderable() end
function flags.TabBar.AutoSelectNewTabs() end
function flags.TabBar.TabListPopupButton() end
function flags.TabBar.NoCloseWithMiddleMouseButton() end
function flags.TabBar.NoTabListScrollingButtons() end
function flags.TabBar.NoTooltip() end
function flags.TabBar.FittingPolicyResizeDown() end
function flags.TabBar.FittingPolicyScroll() end
function flags.TabBar.NoClosed() end


function flags.DragDrop.SourceNoPreviewTooltip() end
function flags.DragDrop.SourceNoDisableHover() end
function flags.DragDrop.SourceNoHoldToOpenOthers() end
function flags.DragDrop.SourceAllowNullID() end
function flags.DragDrop.SourceExtern() end
function flags.DragDrop.SourceAutoExpirePayload() end
function flags.DragDrop.AcceptBeforeDelivery() end
function flags.DragDrop.AcceptNoDrawDefaultRect() end
function flags.DragDrop.AcceptNoPreviewTooltip() end
function flags.DragDrop.AcceptPeekOnly() end

function enum.StyleCol.Text() end
function enum.StyleCol.TextDisabled() end
function enum.StyleCol.WindowBg() end              -- Background of normal windows
function enum.StyleCol.ChildBg() end               -- Background of child windows
function enum.StyleCol.PopupBg() end               -- Background of popups, menus, tooltips windows
function enum.StyleCol.Border() end
function enum.StyleCol.BorderShadow() end
function enum.StyleCol.FrameBg() end               -- Background of checkbox, radio button, plot, slider, text input
function enum.StyleCol.FrameBgHovered() end
function enum.StyleCol.FrameBgActive() end
function enum.StyleCol.TitleBg() end
function enum.StyleCol.TitleBgActive() end
function enum.StyleCol.TitleBgCollapsed() end
function enum.StyleCol.MenuBarBg() end
function enum.StyleCol.ScrollbarBg() end
function enum.StyleCol.ScrollbarGrab() end
function enum.StyleCol.ScrollbarGrabHovered() end
function enum.StyleCol.ScrollbarGrabActive() end
function enum.StyleCol.CheckMark() end
function enum.StyleCol.SliderGrab() end
function enum.StyleCol.SliderGrabActive() end
function enum.StyleCol.Button() end
function enum.StyleCol.ButtonHovered() end
function enum.StyleCol.ButtonActive() end
function enum.StyleCol.Header() end
function enum.StyleCol.HeaderHovered() end
function enum.StyleCol.HeaderActive() end
function enum.StyleCol.Separator() end
function enum.StyleCol.SeparatorHovered() end
function enum.StyleCol.SeparatorActive() end
function enum.StyleCol.ResizeGrip() end
function enum.StyleCol.ResizeGripHovered() end
function enum.StyleCol.ResizeGripActive() end
function enum.StyleCol.Tab() end
function enum.StyleCol.TabHovered() end
function enum.StyleCol.TabActive() end
function enum.StyleCol.TabUnfocused() end
function enum.StyleCol.TabUnfocusedActive() end
function enum.StyleCol.DockingPreview() end
function enum.StyleCol.DockingEmptyBg() end        -- Background color for empty node (e.g. CentralNode with no window docked into it)
function enum.StyleCol.PlotLines() end
function enum.StyleCol.PlotLinesHovered() end
function enum.StyleCol.PlotHistogram() end
function enum.StyleCol.PlotHistogramHovered() end
function enum.StyleCol.TextSelectedBg() end
function enum.StyleCol.DragDropTarget() end
function enum.StyleCol.NavHighlight() end          -- Gamepad/keyboard: current highlighted item
function enum.StyleCol.NavWindowingHighlight() end -- Highlight window when using CTRL+TAB
function enum.StyleCol.NavWindowingDimBg() end     -- Darken/colorize entire screen behind the CTRL+TAB window list, when active
function enum.StyleCol.ModalWindowDimBg() end      -- Darken/colorize entire screen behind a modal window, when one is active
function enum.StyleCol.COUNT() end

function enum.StyleVar.Alpha() end               -- float     Alpha
function enum.StyleVar.WindowPadding() end       -- ImVec2    WindowPadding
function enum.StyleVar.WindowRounding() end      -- float     WindowRounding
function enum.StyleVar.WindowBorderSize() end    -- float     WindowBorderSize
function enum.StyleVar.WindowMinSize() end       -- ImVec2    WindowMinSize
function enum.StyleVar.WindowTitleAlign() end    -- ImVec2    WindowTitleAlign
function enum.StyleVar.ChildRounding() end       -- float     ChildRounding
function enum.StyleVar.ChildBorderSize() end     -- float     ChildBorderSize
function enum.StyleVar.PopupRounding() end       -- float     PopupRounding
function enum.StyleVar.PopupBorderSize() end     -- float     PopupBorderSize
function enum.StyleVar.FramePadding() end        -- ImVec2    FramePadding
function enum.StyleVar.FrameRounding() end       -- float     FrameRounding
function enum.StyleVar.FrameBorderSize() end     -- float     FrameBorderSize
function enum.StyleVar.ItemSpacing() end         -- ImVec2    ItemSpacing
function enum.StyleVar.ItemInnerSpacing() end    -- ImVec2    ItemInnerSpacing
function enum.StyleVar.IndentSpacing() end       -- float     IndentSpacing
function enum.StyleVar.ScrollbarSize() end       -- float     ScrollbarSize
function enum.StyleVar.ScrollbarRounding() end   -- float     ScrollbarRounding
function enum.StyleVar.GrabMinSize() end         -- float     GrabMinSize
function enum.StyleVar.GrabRounding() end        -- float     GrabRounding
function enum.StyleVar.TabRounding() end         -- float     TabRounding
function enum.StyleVar.ButtonTextAlign() end     -- ImVec2    ButtonTextAlign
function enum.StyleVar.SelectableTextAlign() end -- ImVec2    SelectableTextAlign
function enum.StyleVar.COUNT() end

function enum.MouseCursor.None() end
function enum.MouseCursor.Arrow() end
function enum.MouseCursor.TextInput() end
function enum.MouseCursor.ResizeAll() end
function enum.MouseCursor.ResizeNS() end
function enum.MouseCursor.ResizeEW() end
function enum.MouseCursor.ResizeNESW() end
function enum.MouseCursor.ResizeNWSE() end
function enum.MouseCursor.Hand() end
function enum.MouseCursor.COUNT() end

function IO.WantCaptureMouse()          -- When io.WantCaptureMouse is true, imgui will use the mouse inputs, do not dispatch them to your main game/application (in both cases, always pass on mouse inputs to imgui). (e.g. unclicked mouse is hovering over an imgui window, widget is active, mouse was clicked over an imgui window, etc.).
function IO.WantCaptureKeyboard()       -- When io.WantCaptureKeyboard is true, imgui will use the keyboard inputs, do not dispatch them to your main game/application (in both cases, always pass keyboard inputs to imgui). (e.g. InputText active, or an imgui window is focused and navigation is enabled, etc.).
function IO.WantTextInput()             -- Mobile/console: when io.WantTextInput is true, you may display an on-screen keyboard. This is set by ImGui when it wants textual keyboard input to happen (e.g. when a InputText widget is active).
--WantSetMousePos:imgui want to override the system mouse pos by imgui.mousepos,need to implement on platform
function IO.WantSetMousePos()           -- MousePos has been altered, back-end should reposition mouse on next frame. Set only when ImGuiConfigFlags_NavEnableSetMousePos flag is enabled.
function IO.WantSaveIniSettings()       -- When manual .ini load/save is active (io.IniFilename == NULL), this will be set to notify your application that you can call SaveIniSettingsToMemory() and save yourself. IMPORTANT: You need to clear io.WantSaveIniSettings yourself.
function IO.NavActive()                 -- Directional navigation is currently allowed (will handle ImGuiKey_NavXXX events) = a window is focused and it doesn't use the ImGuiWindowFlags_NoNavInputs flag.
function IO.NavVisible()                -- Directional navigation is visible and allowed (will handle ImGuiKey_NavXXX events).
function IO.Framerate()                 -- Application framerate estimation, in frame per second. Solely for convenience. Rolling average estimation based on IO.DeltaTime over 120 frames
function IO.MetricsRenderVertices()     -- Vertices output during last call to Render()
function IO.MetricsRenderIndices()      -- Indices output during last call to Render() = number of triangles * 3
function IO.MetricsRenderWindows()      -- Number of visible windows
function IO.MetricsActiveWindows()      -- Number of active windows
function IO.MetricsActiveAllocations()  -- Number of active allocations, updated by MemAlloc/MemFree based on current context. May be off if you have multiple imgui contexts.

