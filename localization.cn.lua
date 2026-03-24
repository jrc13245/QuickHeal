-- QuickHeal zhCN localization (WoW 1.12.x)
-- Loads only on a Chinese client.
if GetLocale() ~= "zhCN" then return end

-- ===== Spells =====
-- Shaman
QUICKHEAL_SPELL_CHAIN_HEAL         = "治疗链"
QUICKHEAL_SPELL_LESSER_HEALING_WAVE = "次级治疗波"
QUICKHEAL_SPELL_HEALING_WAVE       = "治疗波"

-- Priest
QUICKHEAL_SPELL_LESSER_HEAL        = "次级治疗术"
QUICKHEAL_SPELL_HEAL               = "治疗术"
QUICKHEAL_SPELL_GREATER_HEAL       = "强效治疗术"
QUICKHEAL_SPELL_FLASH_HEAL         = "快速治疗"
QUICKHEAL_SPELL_RENEW              = "恢复"
QUICKHEAL_SPELL_PRAYER_OF_HEALING  = "治疗祷言"

-- Paladin
QUICKHEAL_SPELL_HOLY_LIGHT         = "圣光术"
QUICKHEAL_SPELL_FLASH_OF_LIGHT     = "圣光闪现"
QUICKHEAL_SPELL_HOLY_SHOCK         = "神圣震击"

-- Druid
QUICKHEAL_SPELL_HEALING_TOUCH      = "治疗之触"
QUICKHEAL_SPELL_REGROWTH           = "愈合"
QUICKHEAL_SPELL_REJUVENATION       = "回春术"

-- ===== UI strings used in XML/tooltips/buttons =====
-- Section titles shown by XML via text="FILTER_..." lookups
FILTER_MTLIST_SHOW                 = "主坦克"
FILTER_MELEEDPSLIST_SHOW           = "近战输出"

-- Tooltip titles (shown on OnEnter in QuickHeal.xml)
QH_STR_MTLIST                      = "主坦克"
QH_STR_MELEEDPSLIST                = "近战输出"

-- Clear-button labels (set at OnLoad in XML)
QH_CLR_MT_PRIO                     = "清"
QH_CLR_MELEEDPSLIST                = "清"

-- ===== Keybindings (these override English if present) =====
BINDING_HEADER_QUICKHEAL                              = "QuickHeal"
BINDING_NAME_QUICKHEAL_HEAL                           = "施放治疗"
BINDING_NAME_QUICKHEAL_HOT                            = "施放持续治疗"
BINDING_NAME_QUICKHEAL_HEALMT                         = "治疗主坦克"
BINDING_NAME_QUICKHEAL_HOTMT                          = "持续治疗主坦克"
BINDING_NAME_QUICKHEAL_HEALNONMT                      = "治疗非主坦克"
BINDING_NAME_QUICKHEAL_HEALSELF                       = "治疗自己"
BINDING_NAME_QUICKHEAL_HEALTARGET                     = "治疗当前目标"
BINDING_NAME_QUICKHEAL_HEALTARGETTARGET               = "治疗目标的目标"
BINDING_NAME_QUICKHEAL_HEALPARTY                      = "治疗小队"
BINDING_NAME_QUICKHEAL_HEALSUBGROUP                   = "治疗子小队"
BINDING_NAME_QUICKHEAL_HOTSUBGROUP                    = "持续治疗子小队"
BINDING_NAME_QUICKHEAL_HOTFH                          = "持续治疗（忽略血量）"
BINDING_NAME_QUICKHEAL_TOGGLEHEALTHYTHRESHOLD         = "切换健康阈值 0/100%"
BINDING_NAME_QUICKHEAL_SHOWDOWNRANKWINDOW             = "显示/隐藏降阶窗口"
