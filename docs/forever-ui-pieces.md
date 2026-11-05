Verified against Gethe/wow-ui-source branch forever on 2026-11-05.

# Forever UI pieces for GuildGrudge

## How to read this file

- Every file path starts at `Interface/AddOns/` in the `forever` branch. For example, `Blizzard_SharedXML/PortraitFrame.lua` means `Interface/AddOns/Blizzard_SharedXML/PortraitFrame.lua`.
- Line numbers match branch `forever` as read on 2026-11-05. Snippets are copied or adapted from the named Blizzard file, and an adapted snippet says so.
- `NOT FOUND` means the name does not appear in the Blizzard UI source that was read. The name may still exist in the game client.
- Fetched copies of the source files are under `/tmp/claude-1000/-home-daniel-source-repos-GuildGrudge/738338f8-ba74-4857-9f99-9b79fd4e4e96/scratchpad/src/Interface/AddOns/`.

## 1. Portrait window frame (PortraitFrameTemplate, ButtonFrameTemplate)

**Names**

- `PortraitFrameTemplate`, `PortraitFrameTemplateNoCloseButton`, `PortraitFrameTemplateMinimizable`, `PortraitFrameFlatTemplate`
- `ButtonFrameTemplate`, `ButtonFrameTemplateMinimizable`, `ButtonFrameBaseTemplate`
- `ButtonFrameTemplate_HidePortrait` and `ButtonFrameTemplate_ShowPortrait` are Lua functions, not templates. They change the border and the portrait visibility.

**Files**

- `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml`: PortraitFrameBaseTemplate at line 566, PortraitFrameTemplate at 658, ButtonFrameBaseTemplate at 687, ButtonFrameTemplate at 711, ButtonFrameTemplateMinimizable at 731.
- `Blizzard_SharedXML/PortraitFrame.lua`: `TitledPanelMixin` and `PortraitFrameMixin` (lines 1 to 100).
- `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua`: `ButtonFrameTemplate_HidePortrait` at line 111, `ButtonFrameTemplate_ShowPortrait` at 119.
- `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml`: `UIPanelCloseButtonDefaultAnchors` at line 153. The Lua mixin is in `SharedUIPanelTemplates.lua` at line 137.

**Size**

- `PortraitFrameBaseTemplate` (and so every template that inherits it) defaults to 338 by 424 (XML line 571).
- FriendsFrame overrides the size to 385 by 424 (`Blizzard_FriendsFrame/Mainline/FriendsFrame.xml`, line 479).

**Child keys**

- `NineSlice` (NineSlicePanelTemplate). The border layout comes from `SetBorder(layoutName)`.
- `PortraitContainer.portrait`: a 62 by 62 texture at TOPLEFT -5, 7. It is masked to a circle.
- `TitleContainer.TitleText`: a `GameFontNormal` FontString.
- `CloseButton`: a `UIPanelCloseButtonDefaultAnchors` button. It is 24 by 24 and anchored TOPRIGHT at 1, 0 (`SharedUIPanelTemplates.lua` lines 139 to 142).
- `Inset`: `InsetFrameTemplate`, created by `ButtonFrameTemplate` (XML lines 713 to 717). Default anchors are TOPLEFT 4, -60 and BOTTOMRIGHT -6, 26.
- `Bg` and `TopTileStreaks` (ButtonFrameBaseTemplate and PortraitFrameTexturedBaseTemplate).
- `FrameGlow`, `LeftJumpHint`, `RightJumpHint`, `FocusJumpHint`.

**Title and portrait setters** (all on `PortraitFrameMixin`, which every template above uses)

- `SetTitle(title)` (from `TitledPanelMixin`, PortraitFrame.lua line 12). It sets `TitleContainer.TitleText`.
- `SetTitleColor(color)`, `SetTitleFormatted(fmt, ...)`, `SetTitleMaxLinesAndHeight(maxLines, height)`.
- `SetPortraitToAsset(texture)` (line 47). It calls `GetPortrait():SetTexture(texture)`.
- `SetPortraitTextureRaw(texture)` (line 59). It does the same thing as `SetPortraitToAsset`.
- `SetPortraitAtlasRaw(atlas, ...)` (line 63).
- `SetPortraitToClassIcon(classFilename)` (line 67). See section 6.
- `SetPortraitTexCoord(...)` (line 88), `SetPortraitShown(shown)` (line 92), `SetPortraitTextureSizeAndOffset(size, offsetX, offsetY)` (line 96).
- `GetPortrait()` returns `PortraitContainer.portrait`.

**Snippet** (from `Blizzard_FriendsFrame/Mainline/FriendsFrame.lua`, `FriendsIgnoreListMixin:InitializeFrameVisuals`, lines 2764 to 2771, the ignore-list window that is a `ButtonFrameTemplate`)

```lua
ButtonFrameTemplate_HidePortrait(self);
self:SetTitle(IGNORE_LIST);

self.Inset:ClearAllPoints();
self.Inset:SetPoint("TOPLEFT", self, "TOPLEFT", 11, -28);
self.Inset:SetPoint("BOTTOMRIGHT", self, "BOTTOMRIGHT", -6, 36);
```

**Notes**

- The frame in the Blizzard snippet is a child window. Its XML is at `Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` line 873, and it uses `inherits="ButtonFrameTemplate"`.
- `ButtonFrameTemplate_ShowPortrait(self)` shows the portrait again and sets the `PortraitFrameTemplate` border. `ButtonFrameTemplate_HidePortrait(self)` sets the `ButtonFrameTemplateNoPortrait` border and hides the portrait.
- No Blizzard code in the read files calls `SetPortraitToAsset` or `SetPortraitTextureRaw` on a real frame. The setter is defined and documented only in `PortraitFrame.lua`. Its caller is NOT FOUND.
- FriendsFrame sets its own title text (`FriendsFrameTitleText`, FriendsFrame.xml line 490) and its own icon texture (line 482). It does not use `SetTitle`.

## 2. SearchBoxTemplate

**Names**

- `SearchBoxTemplate` (EditBox). Variant: `SearchBoxNineSliceTemplate`.
- `InputBoxInstructionsTemplate` (the base template, which has the `Instructions` FontString).

**Files**

- Templates: `Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml`. `InputBoxInstructionsTemplate` is at lines 180 to 206. `SearchBoxTemplate` is at lines 209 to 257.
- Functions: `Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.lua`. `SearchBoxTemplate_OnLoad` is at line 175, `SearchBoxTemplate_OnEditFocusLost` at 180, `SearchBoxTemplate_OnEditFocusGained` at 187, `SearchBoxTemplate_OnTextChanged` at 192, `SearchBoxTemplate_ClearText` at 203, `ClearButtonMixin` at 213.

**Size**

- The template sets no size. The parent sets it. `WhoFrameEditBox` in `Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` (line 911) sets `<Size y="20"/>` and anchors it at the bottom of its parent.

**Child keys**

- `Instructions`: a FontString (`GameFontDisableSmall`, color 0.35 gray) from `InputBoxInstructionsTemplate` (XML line 189).
- `searchIcon`: a texture with atlas `common-search-magnifyingglass` (XML line 215).
- `clearButton`: a button with `mixin="ClearButtonMixin"`, size 17 by 17, hidden by default (XML line 224). Its `Icon` texture uses atlas `common-search-clearbutton`.

**Instruction text**

- Set it with a KeyValue named `instructionText`. The default value is the global `SEARCH` (XML line 211). `WhoFrameEditBox` sets `WHO_LIST_SEARCH_INSTRUCTIONS` instead (FriendsFrame.xml line 913).

**OnTextChanged hookup**

- The template already runs `SearchBoxTemplate_OnTextChanged` for `OnTextChanged`. The XML binds it at `InputBoxTemplates.xml` line 255. You do not need to bind it again.
- If your own mixin overrides `OnTextChanged`, call `SearchBoxTemplate_OnTextChanged(self)` from it. `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua` line 2305 does this in `SearchBoxListMixin:OnTextChanged`.

**Snippet** (adapted from `Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` lines 911 to 920)

```xml
<EditBox name="GuildGrudgeSearchBox" inherits="SearchBoxTemplate" autoFocus="false">
    <KeyValues>
        <KeyValue key="instructionText" value="SEARCH" type="global"/>
    </KeyValues>
    <Size y="20"/>
    <Anchors>
        <Anchor point="BOTTOMLEFT" x="18" y="32"/>
        <Anchor point="BOTTOMRIGHT" x="-13" y="32"/>
    </Anchors>
</EditBox>
```

**Notes**

- The clear button's `OnClick` runs `ClearButtonMixin:OnClick`, which calls `SearchBoxTemplateClearButton_OnClick` (`InputBoxTemplates.lua` lines 208 and 233). That function clears the text and calls `ClearFocus`.

## 3. ScrollBox list (WowScrollBoxList, MinimalScrollBar, linear view)

**Names**

- `WowScrollBoxList`: the data-provider ScrollBox frame. Defined in `Blizzard_SharedXML/Shared/Scroll/ScrollTemplates.xml` line 4. It has no default size. Anchors set the size.
- `WowScrollBox`: a static ScrollBox with no data provider (ScrollTemplates.xml line 12).
- `MinimalScrollBar`: an `EventFrame` scroll bar. Defined in `Blizzard_SharedXML/Shared/Scroll/MinimalScrollBar.xml` line 15. Default size is 8 by 560 (line 16).
- `WowTrimScrollBar`: an alternate bar (`Blizzard_SharedXML/Shared/Scroll/TrimScrollBar.xml` line 25).
- `CreateScrollBoxListLinearView(top, bottom, left, right, spacing)`: `Blizzard_SharedXML/Shared/Scroll/ScrollBoxLinearView.lua` line 246. All arguments are optional.
- `ScrollUtil.InitScrollBoxListWithScrollBar(scrollBox, scrollBar, view)`: `Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua` line 137.
- `CreateDataProvider()`: used in `Blizzard_FriendsFrame/Mainline/FriendsFrame.lua` (line 827) and `Blizzard_Menu/Menu.lua`. The definition is NOT FOUND in the read source.
- `scrollBox:SetDataProvider(dataProvider, retainScrollPosition)`: `Blizzard_SharedXML/Shared/Scroll/ScrollBox.lua` line 703.
- `ScrollBoxConstants.RetainScrollPosition`: `ScrollBox.lua` lines 12 to 17.

**Row setup: SetElementInitializer, SetElementFactory, SetElementExtent**

- `view:SetElementInitializer(frameTemplateOrFrameType, initializer)`: `Blizzard_SharedXML/Shared/Scroll/ScrollBoxListView.lua` lines 496 to 507. It calls `SetElementFactory` and passes the string on to `factory`.
- The comment above it (lines 480 to 495) says to use `SetElementInitializer` for one template or one basic frame type, for example `SetElementInitializer("Button", Initializer)`. So a Lua-only row can use the plain frame type `"Button"` with no XML template. The factory engine code is NOT FOUND in the source, because `CreateFrameFactory` is not defined in the read files.
- `view:SetElementFactory(function(factory, elementData) ... end)`: `ScrollBoxListView.lua` lines 509 to 537. Use it when rows have different types. `FriendsFrame.lua` lines 345 to 360 shows this.
- `view:SetElementExtent(height)`: `Blizzard_SharedXML/Shared/Scroll/ScrollBoxLinearView.lua` line 102.
- `view:SetElementExtentCalculator(function(dataIndex, elementData) return height end)`: `ScrollBoxLinearView.lua` line 107. Used in `FriendsFrame.lua` lines 387 to 391 and `Blizzard_Menu/Menu.lua` lines 1810 to 1812.

**Can the row be a plain Button with no XML?**

- Yes, in principle. `SetElementInitializer("Button", fn)` works without an XML template. The source does not show a complete Lua-only example that builds font strings or textures on the new button. The usual Blizzard pattern uses an XML template such as `WhoListButtonTemplate` (`Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` line 384). If the rows need several child regions, use an XML virtual template instead.
- The `created` flag pattern in the `ScrollBoxListView.lua` comment (lines 487 to 493) runs one-time setup the first time a frame is used.

**XML for the list and bar** (adapted from `Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` lines 1063 to 1076)

```xml
<Frame parentKey="ScrollBox" inherits="WowScrollBoxList">
    <Size x="302" y="272"/>
    <Anchors>
        <Anchor point="TOPLEFT" relativeKey="$parent.$parent.Inset" x="4" y="-4"/>
        <Anchor point="BOTTOMRIGHT" relativeKey="$parent.$parent.Inset" x="-22" y="48"/>
    </Anchors>
</Frame>
<EventFrame parentKey="ScrollBar" inherits="MinimalScrollBar">
    <Anchors>
        <Anchor point="TOPLEFT" relativeKey="$parent.ScrollBox" relativePoint="TOPRIGHT" x="5" y="-4"/>
        <Anchor point="BOTTOMLEFT" relativeKey="$parent.ScrollBox" relativePoint="BOTTOMRIGHT" x="5" y="-10"/>
    </Anchors>
</EventFrame>
```

**Lua setup and data** (adapted from `FriendsFrame.lua` lines 380 to 393, 827, and 898, and from `Blizzard_Menu/Menu.lua` lines 1801 to 1821)

```lua
local view = CreateScrollBoxListLinearView();
view:SetElementInitializer("Button", function(button, elementData)
    -- Set text and textures on the row. Use the created flag for one-time setup.
end);
view:SetElementExtent(24);
ScrollUtil.InitScrollBoxListWithScrollBar(self.ScrollBox, self.ScrollBar, view);

local dataProvider = CreateDataProvider();
dataProvider:Insert({ name = "Example" });
self.ScrollBox:SetDataProvider(dataProvider, ScrollBoxConstants.RetainScrollPosition);
```

**Notes**


## 4. Tabs at the bottom of a frame

**Current Blizzard usage on this branch**

- Bottom tabs (below the frame): `PanelTabButtonTemplate`. FriendsFrame uses it for its four bottom tabs (`FriendsFrameTab1` to `FriendsFrameTab4`). These tabs are the pattern to copy for a bottom tab row.
- The newer `TabSystemTemplate` and `TabSystemOwnerTemplate` are used by FriendsFrame for its header tabs at the top of the frame (`FriendsFrame.xml` lines 499 to 511).
- CommunitiesFrame uses `CommunitiesFrameTabTemplate`, which inherits `RightSideTabTemplate` (`Blizzard_Communities/CommunitiesTabs.xml` line 4). Those are side tabs, not bottom tabs.

**PanelTabButtonTemplate**

- Defined in `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` line 932. Size is 10 by 32 (line 933). Its `parentArray="Tabs"` puts each tab into the owner's `Tabs` array.
- Lua mixin: `PanelTabButtonMixin` (`Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua` line 251). It resizes the tab on show and on display-size change, using the owner's `tabPadding`, `minTabWidth`, and `maxTabWidth`.
- Child keys: `Text` (ButtonText), `LeftActive`, `RightActive`, `MiddleActive`, `Left`, `Right`, `Middle`, and the highlight textures. Fonts: `GameFontNormalSmall` and `GameFontHighlightSmall`.
- Helpers: `PanelTemplates_SetNumTabs(frame, n)` (line 542), which calls `PanelTemplates_AnchorTabs` (line 558). `PanelTemplates_SetTab(frame, id)` (line 441). `PanelTemplates_TabResize(tab, padding, absoluteSize, minWidth, maxWidth, absoluteTextSize)` (line 477). `PanelTemplates_SetTabShown(frame, index, shown)` (line 597). `PanelTemplates_SetTabEnabled` (line 566).

**Anchor for the first tab** (FriendsFrame.xml lines 1098 to 1105)

```xml
<Button name="FriendsFrameTab1" inherits="FriendsFrameTabTemplate" id="1" text="CONTACTS_TAB_TITLE" collapsesLayout="true">
    <Anchors>
        <Anchor point="TOPLEFT" relativePoint="BOTTOMLEFT" x="5" y="2"/>
    </Anchors>
</Button>
<Button name="FriendsFrameTab2" inherits="FriendsFrameTabTemplate" id="2" text="WHO" collapsesLayout="true"/>
```

The first tab has no `relativeKey`, so it anchors to its parent frame. The other tabs get their anchors from `PanelTemplates_SetNumTabs`.

Lua calls from `FriendsFrame.lua`:

```lua
PanelTemplates_SetNumTabs(FriendsFrame, FRIEND_TAB_COUNT);  -- line 291
PanelTemplates_SetTab(FriendsFrame, 2);                      -- line 1103
```

`FriendsFrameTabTemplate` is `PanelTabButtonTemplate` plus a click handler mixin (`FriendsFrame.xml` line 472).

**Notes**

- The tab lookup uses the `Tabs` array when it exists. Otherwise it uses the global name `<Frame>Tab<n>` (`SharedUIPanelTemplates.lua` lines 450 to 452). Put the tabs in a `Tabs` array, or name them `MyFrameTab1`, `MyFrameTab2`, and so on.
- `PanelTabButtonMixin` reads `tabPadding`, `minTabWidth`, and `maxTabWidth` from the tab's parent frame (`SharedUIPanelTemplates.lua` lines 258 to 266). Set those fields on the owner frame if you need custom tab widths. The source does not show a bottom tab row that sets them.

## 5. Small square icon buttons

**Names and files**

- `SquareIconButtonTemplate` (Button). Defined in `Blizzard_SharedXML/Shared/Button/IconButtonTemplate.xml` at line 40. Mixin: `SquareIconButtonMixin`, in `IconButtonTemplate.lua` at line 53.
- `IconButtonTemplate` (line 4) is the base. Mixin: `IconButtonMixin` (`IconButtonTemplate.lua` line 2).
- `CommonSquareIconButtonTemplate` (line 59) is a larger 48 by 48 variant with atlas art.
- `RefreshButtonTemplate` (`Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` line 1332). It inherits `SquareIconButtonTemplate` and sets `iconAtlas` to `UI-RefreshButton`.
- `UIPanelSquareButton` (`Blizzard_UIPanelTemplates/Mainline/UIPanelTemplates.xml` line 39). It is 26 by 26 and uses the file `Interface\Buttons\SquareButtonTextures`. Its child is `icon`, 12 by 12.
- `UIPanelIconDropdownButtonTemplate` (`SharedUIPanelTemplates.xml` line 2312) is a `DropdownButton`. It has `Icon` at atlas `questlog-icon-setting` (line 2316).

**Size**

- `SquareIconButtonTemplate` is 32 by 32 (`IconButtonTemplate.xml` line 44). The default icon size is 16 (KeyValue `iconSize`, line 42).

**Child keys**

- `Icon`: the icon texture (`IconButtonTemplate.xml` line 25). `IconButtonMixin:OnLoad` sizes it from `iconSize`.
- `NormalTexture`, `PushedTexture`, `DisabledTexture`, and `HighlightTexture` (file-based in `SquareIconButtonTemplate`).

**Set the icon**

- In XML: use a KeyValue `iconAtlas` (atlas name) or `icon` (file path). `IconButtonMixin:OnLoad` reads them (`IconButtonTemplate.lua` lines 4 to 9).
- In Lua: `button:SetAtlas(atlas, useAtlasSize)` (`IconButtonTemplate.lua` line 44) or `button:SetIcon(file)` (line 40).

**Snippet** (adapted from `Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` lines 545 to 550, and `SharedUIPanelTemplates.xml` line 1332)

```xml
<Button parentKey="ToolbarButton" inherits="SquareIconButtonTemplate">
    <Size x="32" y="32"/>
    <KeyValues>
        <KeyValue key="iconAtlas" value="UI-RefreshButton" type="string"/>
        <KeyValue key="iconSize" value="16" type="number"/>
    </KeyValues>
</Button>
```

**Notes**


## 6. Class icons and class colors

**Class icon atlases**

- Atlas names such as `classicon-<class>` and `groupfinder-icon-class-<class>`: NOT FOUND in the read source.

**Class icon textures that are used**

- `Interface/TargetingFrame/UI-Classes-Circles`. Used by `PortraitFrameMixin:SetPortraitToClassIcon` (`Blizzard_SharedXML/PortraitFrame.lua` lines 67 to 71). The code reads texture coordinates from `CLASS_ICON_TCOORDS[string.upper(classFilename)]`.
- `CLASS_ICON_TCOORDS`: the definition is NOT FOUND in the read source. It is used only in `PortraitFrame.lua` line 69.
- `Interface\Glues\CharacterCreate\UI-CharacterCreate-Classes`. Used as the file of a 16 by 16 texture named `Class` in `Blizzard_Communities/CommunitiesMemberList.xml` line 194. The Lua that sets its texture coordinates was NOT FOUND in the read files.

**Class colors**

- `Blizzard_SharedXML/ClassColors.lua` builds the global table `RAID_CLASS_COLORS`. It loops over 15 class file names (`HUNTER` to `TRAVELER`) and sets each entry to `C_ClassColor.GetClassColor(className)` (line 24). It also sets `color.colorStr` with `GenerateHexColor()` (line 29).
- `C_ClassColor.GetClassColor(className)` is documented in `Blizzard_APIDocumentationGenerated/ClassColorDocumentation.lua` (line 11).
- `C_ClassColor.GetClassColorObj`: NOT FOUND in the read source.
- The global `GetClassColor(classFilename)` returns four values, and the last is the color code. It is used in `Blizzard_StaticPopup_Game/GameDialogDefs.lua` line 3611 as `local _, _, _, colorCode = GetClassColor(classFilename)`.

**Snippet** (adapted from `Blizzard_FriendsFrame/Mainline/FriendsFrame.lua` line 1019, and from `ColorMixin:GetRGBA` as used in `PortraitFrame.lua` line 9)

```lua
local classColor = RAID_CLASS_COLORS[classFilename];  -- for example "WARRIOR"
if classColor then
    self.Name:SetTextColor(classColor:GetRGBA());
end
```

The keys are class file names in uppercase, such as `WARRIOR` or `DEATHKNIGHT`. `info.filename` is the class key used in FriendsFrame (line 1019).

## 7. Gold coin icon and money text

**Atlas**

- `coin-gold` (also `coin-silver` and `coin-copper`).
- Defined as atlas names in `Blizzard_SharedXML/MoneyFormatter.lua` lines 22 to 24 (`MoneyFormatterConfigMixin.DenominationAtlases`).
- Also in `Blizzard_MoneyFrame/Shared/MoneyFrame.lua` lines 348 to 353, as `{ TextureType.Atlas, "coin-gold" }`.

**Texture path**

- `Interface\MoneyFrame\UI-GoldIcon`: NOT FOUND in the read source.

**Money text helpers**

- `MoneyFormatterUtil.FormatMoney(rawCopper, config)` (`MoneyFormatter.lua` line 224). `rawCopper` is the total in copper.
- `MoneyFormatterUtil.CreateFormatterConfig()` (line 127). It is the same as `CreateAndInitFromMixin(MoneyFormatterConfigMixin)`.
- Presets: `MoneyFormatterPresets.Compact` (line 266) shows only non-zero denominations. `MoneyFormatterPresets.ShowAll` (line 286) shows every denomination.
- Texture markup size: 14 by 14, with x offset 2 (lines 48 to 51). The markup comes from `CreateAtlasMarkup` (line 172). That function is engine code, and its definition is NOT FOUND in the read source.
- `GetMoneyString`: used in `Blizzard_StaticPopup_Game/GameDialog.lua` lines 155 and 161. Its definition is NOT FOUND in the read source.
- `C_CurrencyInfo.GetCoinTextureString`: documented in `Blizzard_APIDocumentationGenerated/CurrencyInfoDocumentation.lua` line 161. No caller was found in the read source. `C_CurrencyInfo.GetCoinIcon` is documented at line 130.

**Snippet** (adapted from the `MoneyFormatterPresets` usage in `MoneyFormatter.lua` lines 266 to 269)

```lua
local config = MoneyFormatterPresets.Compact;
local text = MoneyFormatterUtil.FormatMoney(123456, config);  -- rawCopper value
self.Label:SetText(text);
```

**Notes**

The output text contains atlas markup for each coin. Set it on a FontString with `SetText`. To change the coin size, call `config:SetTextureMarkupOptions(width, height, offsetX, offsetY)`.

## 8. Other icons (skull, eye, note, trophy, plus)

**Raid target icons (skull)**

- The skull texture path (`Interface\TargetingFrame\UI-RaidTargetingIcon_8`): NOT FOUND in the read source.
- `SetRaidTargetIconTexture(texture, index)` is an engine function. `Blizzard_NamePlates/Blizzard_NamePlateRaidTarget.lua` line 13 calls it as `SetRaidTargetIconTexture(self.RaidTargetIcon, self.raidTargetIndex)`. The index-to-icon mapping is NOT FOUND in the read source. Use this function, not a file path.

**Eye, note or quill, trophy or leaderboard, bounty**

- NOT FOUND. No atlas or file with these names was found in the read XML or Lua.

**Plus (add)**

- Atlas `communities-icon-addchannelplus`. Used as `PlusIcon` in `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` line 1829 (`useAtlasSize="true"`, `alphaMode="ADD"`).

**Other icon atlases used in the source**

- `friends-icon-favorites`, used in `Blizzard_FriendsFrame/Mainline/FriendsListTemplates.xml` line 22. Also used as inline markup with `CreateAtlasMarkup(atlas, 16, 16)` in `FriendsListTemplates.lua` line 852. The disabled version is `friends-icon-favorites-dis`.
- `communities-icon-notification`, `Blizzard_Communities/CommunitiesFrame.xml` line 396.
- `groupfinder-icon-redx`, `Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` line 89.
- `collections-icon-favorites`, `Blizzard_Communities/CommunitiesList.xml` line 98.
- `common-search-magnifyingglass` (search icon), `InputBoxTemplates.xml` line 215.

## 9. Row visuals (alternating rows and hover highlight)

**Alternating row helper**

- `ScrollUtil.RegisterAlternateRowBehavior(scrollBox, callback)` (`Blizzard_SharedXML/Shared/Scroll/ScrollUtil.lua` lines 1630 to 1640). After each data range change, it calls `callback(frame, alternate)`. `alternate` is true on even data indexes (`index % 2 == 0`).
- `ScrollUtil.AlternateDataValue(dataProvider, predicate, field, initValue)` (line 1642) sets a value such as `odd` on each data element.
- Callers of these helpers: NOT FOUND in the read files. The callback that draws the row color is therefore not shown in the source.

**Row background atlas**

- `_search-rowbg`. Used as the `background` texture of the search-preview row in `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` line 2085. The atlas fills the row with `TOPLEFT` and `BOTTOMRIGHT` anchors.

**Hover highlight (used in a ScrollBox list)**

- `Interface\QuestFrame\UI-QuestTitleHighlight`, with `alphaMode="ADD"`. Used as `HighlightTexture` in two list rows that run inside `WowScrollBoxList`:
  - `IgnoreListButtonTemplate` (`Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` line 381).
  - `WhoListButtonTemplate` (FriendsFrame.xml line 422). The Who list uses `WowScrollBoxList` (line 1063).
- `Interface\FriendsFrame\UI-FriendsFrame-HighlightBar`, with `alphaMode="ADD"` and `setAllPoints`. Used by `CommunitiesMemberListEntryTemplate` (`Blizzard_Communities/CommunitiesMemberList.xml` line 243). That template starts at line 4.
- Atlas `friends-card-selected` (`alphaMode="ADD"`) for the selected card in `Blizzard_FriendsFrame/Mainline/FriendsListTemplates.xml` line 180.
- `Options_List_Hover`: NOT FOUND in the read source.
- `Interface\QuestFrame\UI-QuestLogTitleHighlight` is used in FriendsFrame.xml line 358. That highlight belongs to the summon button (declared at line 335), not to a list row.

**Snippet** (adapted from `Blizzard_FriendsFrame/Mainline/FriendsFrame.xml` lines 381 and 366)

```xml
<Button name="GuildGrudgeRowTemplate" virtual="true">
    <Size x="298" y="16"/>
    <HighlightTexture file="Interface\QuestFrame\UI-QuestTitleHighlight" alphaMode="ADD"/>
</Button>
```

## 10. Fonts

Each font name below is used by name in Blizzard XML. The object definitions are not in the fetched source tree. The client defines them, so the names exist on this branch. The fetched files contain no `<Font name="GameFontNormal">` declaration.

| Font name | Used in (number of fetched files that use it) | Example |
| --- | --- | --- |
| `GameFontNormal` | 8 | `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` line 608 (portrait frame title) |
| `GameFontHighlight` | 8 | `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` |
| `GameFontHighlightSmall` | 13 | `Blizzard_Minimap/Mainline/Minimap.xml` |
| `GameFontDisableSmall` | 3 | `Blizzard_SharedXML/Shared/InputBox/InputBoxTemplates.xml` line 189 (search instructions) |
| `GameFontNormalLarge` | 2 | `Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.xml` |
| `GameFontNormalSmall` | 9 | `Blizzard_SharedXML/Shared/TabSystem/TabSystemTemplates.lua` |

Notes:

- `InputBoxTemplates.xml` line 205 sets `GameFontHighlightSmall` as the font for the edit box text.
