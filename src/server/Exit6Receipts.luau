-- EXIT 6 developer-product receipts: the single owner of
-- MarketplaceService.ProcessReceipt (an experience gets exactly one).
-- Systems register a handler per product id; the handler must persist the
-- purchase before returning true. Unknown ids and failures return
-- NotProcessedYet, so Roblox re-delivers the receipt later and nobody is
-- charged for nothing.
local MarketplaceService = game:GetService("MarketplaceService")

local Receipts = {}
local handlers = {}

function Receipts.Register(productId, handler)
	assert(type(productId) == "number" and productId > 0, "real developer product ids only")
	assert(handlers[productId] == nil, "product " .. productId .. " already has a handler")
	handlers[productId] = handler
end

function Receipts.Handled(productId)
	return handlers[productId] ~= nil
end

MarketplaceService.ProcessReceipt = function(info)
	local handler = handlers[info.ProductId]
	if not handler then
		warn("[Exit6Receipts] no handler for product " .. tostring(info.ProductId) .. "; receipt left pending")
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local ok, granted = pcall(handler, info)
	if not ok then
		warn("[Exit6Receipts] handler error for product " .. tostring(info.ProductId) .. ": " .. tostring(granted))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	return granted == true and Enum.ProductPurchaseDecision.PurchaseGranted
		or Enum.ProductPurchaseDecision.NotProcessedYet
end

return Receipts
