---
id: modules_issuer_MintBurn_MintBurnModule
title: MintBurnModule
---

<div class="contract-doc"><div class="contract"><h2 class="contract-header"><span class="contract-kind">contract</span> MintBurnModule</h2><p class="base-contracts"><span>is</span> <a href="modules_ModuleBase_IssuerModuleBase.html">IssuerModuleBase</a></p><div class="source">Source: <a href="git+https://github.com/SFT-Protocol/security-token/blob/v0.11.2/contracts/modules/issuer/MintBurn.sol" target="_blank">modules/issuer/MintBurn.sol</a></div></div><div class="index"><h2>Index</h2><ul><li><a href="modules_issuer_MintBurn_MintBurnModule.html#TokensBurned">TokensBurned</a></li><li><a href="modules_issuer_MintBurn_MintBurnModule.html#TokensMinted">TokensMinted</a></li><li><a href="modules_issuer_MintBurn_MintBurnModule.html#burn">burn</a></li><li><a href="modules_issuer_MintBurn_MintBurnModule.html#">fallback</a></li><li><a href="modules_issuer_MintBurn_MintBurnModule.html#getBindings">getBindings</a></li><li><a href="modules_issuer_MintBurn_MintBurnModule.html#mint">mint</a></li></ul></div><div class="reference"><h2>Reference</h2><div class="events"><h3>Events</h3><ul><li><div class="item event"><span id="TokensBurned" class="anchor-marker"></span><h4 class="name">TokensBurned</h4><div class="body"><code class="signature">event <strong>TokensBurned</strong><span>(address token, uint256 amount) </span></code><hr/><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>token</code> - address</div><div><code>amount</code> - uint256</div></dd></dl></div></div></li><li><div class="item event"><span id="TokensMinted" class="anchor-marker"></span><h4 class="name">TokensMinted</h4><div class="body"><code class="signature">event <strong>TokensMinted</strong><span>(address token, uint256 amount) </span></code><hr/><dl><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>token</code> - address</div><div><code>amount</code> - uint256</div></dd></dl></div></div></li></ul></div><div class="functions"><h3>Functions</h3><ul><li><div class="item function"><span id="burn" class="anchor-marker"></span><h4 class="name">burn</h4><div class="body"><code class="signature">function <strong>burn</strong><span>(address _token, uint256 _value) </span><span>external </span><span>returns  (bool) </span></code><hr/><dl><dt><span class="label-modifiers">Modifiers:</span></dt><dd><a href="modules_ModuleBase_IssuerModuleBase.html#onlyIssuer">onlyIssuer </a></dd><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>_token</code> - address</div><div><code>_value</code> - uint256</div></dd><dt><span class="label-return">Returns:</span></dt><dd>bool</dd></dl></div></div></li><li><div class="item function"><span id="fallback" class="anchor-marker"></span><h4 class="name">fallback</h4><div class="body"><code class="signature">function <strong></strong><span>(address _issuer) </span><span>public </span></code><hr/><dl><dt><span class="label-modifiers">Modifiers:</span></dt><dd></dd><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>_issuer</code> - address</div></dd></dl></div></div></li><li><div class="item function"><span id="getBindings" class="anchor-marker"></span><h4 class="name">getBindings</h4><div class="body"><code class="signature">function <strong>getBindings</strong><span>() </span><span>external </span><span>pure </span><span>returns  (bool[]) </span></code><hr/><dl><dt><span class="label-return">Returns:</span></dt><dd>bool[]</dd></dl></div></div></li><li><div class="item function"><span id="mint" class="anchor-marker"></span><h4 class="name">mint</h4><div class="body"><code class="signature">function <strong>mint</strong><span>(address _token, uint256 _value) </span><span>external </span><span>returns  (bool) </span></code><hr/><dl><dt><span class="label-modifiers">Modifiers:</span></dt><dd><a href="modules_ModuleBase_IssuerModuleBase.html#onlyIssuer">onlyIssuer </a></dd><dt><span class="label-parameters">Parameters:</span></dt><dd><div><code>_token</code> - address</div><div><code>_value</code> - uint256</div></dd><dt><span class="label-return">Returns:</span></dt><dd>bool</dd></dl></div></div></li></ul></div></div></div>