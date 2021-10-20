local element = {}

local unicode = require("unicode")

local richtext = require("citeproc.citeproc-richtext")
local util = require("citeproc.citeproc-util")


local Element = {
  default_options = {},
}

function Element:new ()
  local o = {}
  setmetatable(o, self)
  self.__index = self
  return o
end

Element.option_type = {
  ["et-al-min"] = "integer",
  ["et-al-use-first"] = "integer",
  ["et-al-subsequent-min"] = "integer",
  ["et-al-subsequent-use-first"] = "integer",
  ["near-note-distance"] = "integer",
  ["near"] = "integer",
  ["line-spacing"] = "integer",
  ["names-min"] = "integer",
  ["names-use-first"] = "integer",
  ["limit-day-ordinals-to-day-1"] = "boolean",
  ["punctuation-in-quote"] = "boolean",
  ["et-al-use-last"] = "boolean",
  ["initialize"] = "boolean",
  ["initialize-with-hyphen"] = "boolean",
  ["disambiguate-add-names"] = "boolean",
  ["disambiguate-add-givenname"] = "boolean",
  ["disambiguate-add-year-suffix"] = "boolean",
  ["hanging-indent"] = "boolean",
  ["names-use-last"] = "boolean",
  ["quotes"] = "boolean",
  ["strip-periods"] = "boolean",
}

Element.inheritable_options = {
  -- Style
  ["initialize-with-hyphen"] = true,
  ["page-range-format"] = true,
  ["demote-non-dropping-particle"] = true,
  -- Bibliography
  ["second-field-align"] = true,  -- for use in layout
  -- Date
  ["date-parts"] = true,
  -- Names
  ["and"] = true,
  ["delimiter-precedes-et-al"] = true,
  ["delimiter-precedes-last"] = true,
  ["et-al-min"] = true,
  ["et-al-use-first"] = true,
  ["et-al-use-last"] = true,
  ["et-al-subsequent-min"] = true,
  ["et-al-subsequent-use-first"] = true,
  ["names-min"] = true,
  ["names-use-first"] = true,
  ["names-use-last"] = true,
  ["initialize-with"] = true,
  ["name-as-sort-order"] = true,
  ["sort-separator"] = true,
  ["name-form"] = true,
  ["name-delimiter"] = true,
  ["names-delimiter"] = true,
}

function Element:render (item, context)
  self:debug_info(context)
  context = self:process_context(context)
  return self:render_children(item, context)
end

function Element:render_children (item, context)
  local output = {}
  for i, child in ipairs(self:get_children()) do
    if child:is_element() then
      if child.render == nil then
        local element_name = child:get_element_name()
        util.warning("Unkown type \"" .. element_name .. "\"")
      end
      local str = child:render(item, context)
      table.insert(output, str)
    end
  end
  return self:concat(output, context)
end

function Element:set_base_class (node)
  if node:is_element() then
    local org_meta_table = getmetatable(node)
    setmetatable(node, {__index = function (_, key)
      if self[key] then
        return self[key]
      else
        return org_meta_table[key]
      end
    end})
  end
end

function Element:debug_info (context, debug)
  -- debug = true
  if debug then
    local text = ""
    local level = 0
    if context and context.level then
      level = context.level + 1
    end
    text = text .. string.rep(" ", 2 * level)
    text = text .. self:get_element_name()
    local attrs = {}
    if self._attr then
      for attr, value in pairs(self._attr) do
        table.insert(attrs, attr .. "=\"" .. value .. "\"")
      end
      text = text .. "[" .. table.concat(attrs, " ") .. "]"
    end
    io.stderr:write(text .. "\n")
  end
end

function Element:get_child (type)
  for _, child in ipairs(self:get_children()) do
    if child:get_element_name() == type then
      return child
    end
  end
  return nil
end

function Element:get_style ()
  local style = self:root_node().style
  assert(style ~= nil)
  return style
end

function Element:get_engine ()
  local engine = self:root_node().engine
  assert(engine ~= nil)
  return engine
end

function Element:process_context (context)
  local state = {
    options = {}
  }
  for key, value in pairs(self.default_options) do
    state.options[key] = value
  end
  if context then
    local element_name = self:get_element_name()
    for key, value in pairs(context) do
      if key == "options" then
        for k, v in pairs(context.options) do
          if self.inheritable_options[k] then
            state.options[k] = v
            if element_name == "name" then
              if k == "name-form" then
                state.options["form"] = v
              end
              if k == "name-delimiter" then
                state.options["delimiter"] = v
              end
            elseif element_name == "names" then
              if k == "names-delimiter" then
                state.options["delimiter"] = v
              end
            end
          end
        end
      else
        state[key] = value
      end
    end
    if state.level then
      state.level = state.level + 1
    else
      state.level = 0
    end
  end
  if self._attr then
    for key, value in pairs(self._attr) do
      if self.option_type[key] == "integer" then
        value = tonumber(value)
      elseif self.option_type[key] == "boolean" then
        value = (value == "true")
      end
      state.options[key] = value
    end
  end
  return state
end

function Element:get_option (key, context)
  assert(context ~= nil)
  return context.options[key]
end

function Element:get_locale_option (key)
  local locales = self:get_style():get_locales()
  for i, locale in ipairs(locales) do
    local option = locale:get_option(key)
    if option ~= nil then
      return option
    end
  end
  return nil
end

function Element:get_variable (item, name, context)
  if context.suppressed_variables and context.suppressed_variables[name] then
    return nil
  else
    local res = item[name]
    if type(res) == "table" and res._type == "RichText" then
      res = res:shallow_copy()
    end

    if res and res ~= "" then
      if context.suppress_subsequent_variables then
        context.suppressed_variables[name] = true
      end
    end
    return res
  end
end

function Element:get_macro (name)
  local query = string.format("macro[name=\"%s\"]", name)
  local macro = self:root_node():query_selector(query)[1]
  if not macro then
    error(string.format("Failed to find %s.", query))
  end
  return macro
end

function Element:get_term (name, form, number, gender)
  return self:get_style():get_term(name, form, number, gender)
end

-- Formatting
function Element:escape (str, context)
  return str
  -- return self:get_engine().formatter.text_escape(str)
end

function Element:format(text, context)
  if not text or text == "" then
    return nil
  end
  if text._type ~= "RichText" then
    text = richtext.new(text)
  end
  local attributes = {
    "font-style",
    "font-variant",
    "font-weight",
    "text-decoration",
    "vertical-align",
  }
  for _, attribute in ipairs(attributes) do
    local value = context.options[attribute]
    if value then
      if text.formats[attribute] then
        local new = richtext.new()
        new.contents = {text}
        text = new
      end
      text:add_format(attribute, value)
    end
  end
  return text
end

-- Affixes
function Element:wrap (str, context)
  if not str or str == "" then
    return nil
  end
  local prefix = context.options["prefix"]
  local suffix = context.options["suffix"]
  local res = str
  if prefix and prefix ~= "" then
    res = richtext.concat(prefix, res)
  end
  if suffix and suffix ~= "" then
    res = richtext.concat(res, suffix)
  end
  return res
end

-- Delimiters
function Element:concat (strings, context)
  local delimiter = context.options["delimiter"]
  return richtext.concat_list(strings, delimiter)
end

-- Display
function Element:display(text, context)
  if not text then
    return text
  end
  local value = context.options["display"]
  if not value then
    return text
  end
  if type(text) == "string" then
    text = richtext.new(text)
  end
  text:add_format("display", value)
  return text
end

-- Quotes
function Element:quote (str, context)
  if not str then
    return nil
  end
  if context.sorting then
    return str
  end
  if not str._type == "RichText" then
    str = richtext.new(str)
  end
  local quotes = context.options["quotes"] or false
  if quotes then
    str:add_format("quotes", "true")
  end
  return str
end

-- Strip periods
function Element:strip_periods (str, context)
  if not str then
    return nil
  end
  if str._type ~= "RichText" then
    str = richtext.new(str)
  end
  local strip_periods = context.options["strip-periods"]
  if strip_periods then
    str:strip_periods()
  end
  return str
end

-- Text-case
function Element:case (text, context)
  if not text or text == "" then
    return nil
  end
  if text._type ~= "RichText" then
    text = richtext.new(text)
  end
  local text_case = context.options["text-case"]
  if not text_case then
    return text
  end
  if text_case == "title" then
    -- title case conversion only affects English-language items
    local language = context.item["language"]
    if not language then
      language = self:get_style():get_attribute("default-locale") or "en-US"
    end
    if not util.startswith(language, "en") then
      return text
    end
  end
  text:add_format("text-case", text_case)
  return text
end


element.Element = Element

return element
