pragma solidity ^0.4.24;

import "./open-zeppelin/SafeMath.sol";
import "./KYCRegistrar.sol";
import "./SecurityToken.sol";
import "./Custodian.sol";
import "./components/Modular.sol";
import "./components/MultiSig.sol";

/** @title Issuing Entity */
contract IssuingEntity is Modular, MultiSig {

	using SafeMath32 for uint32;
	using SafeMath for uint256;

	/*
		Each country can have specific limits for each investor class.
		minRating corresponds to the minimum investor level for this country.
		counts[0] and levels[0] == the sum total of counts[1:] and limits[1:]
	*/
	struct Country {
		bool allowed;
		uint8 minRating;
		uint32[8] counts;
		uint32[8] limits;
	}

	struct Account {
		uint192 balance;
		uint8 rating;
		uint8 regKey;
		uint32 custodianCount;
		bool restricted;
		mapping (bytes32 => bool) custodians;
	}

	struct Token {
		bool set;
		bool restricted;
	}

	struct Contract {
		address addr;
		bool restricted;
	}

	bool locked;
	bool mutex;
	Contract[] registrars;
	uint32[8] counts;
	uint32[8] limits;
	mapping (uint16 => Country) countries;
	mapping (bytes32 => Account) accounts;
	mapping (bytes32 => Contract) custodians;
	mapping (address => Token) tokens;
	mapping (string => bytes32) documentHashes;

	event TransferOwnership(
		address indexed token,
		bytes32 indexed from,
		bytes32 indexed to,
		uint256 value
	);
	event BeneficialOwnerSet(
		address indexed custodian,
		bytes32 indexed id,
		bool owned
	);
	event CountryModified(
		uint16 indexed country,
		bool allowed,
		uint8 minrating,
		uint32[8] limits
	);
	event InvestorLimitSet(uint16 indexed country, uint32[8] limits);
	event NewDocumentHash(string indexed document, bytes32 documentHash);
	event RegistrarSet(address indexed registrar, bool allowed);
	event CustodianAdded(address indexed custodian);
	event TokenAdded(address indexed token);
	event InvestorRestriction(bytes32 indexed id, bool allowed);
	event TokenRestriction(address indexed token, bool allowed);
	event GlobalRestriction(bool allowed);
	
	/** @dev check that call originates from a registered, unrestricted token */
	modifier onlyToken() {
		require(tokens[msg.sender].set && !tokens[msg.sender].restricted);
		_;
	}

	/**
		@notice Issuing entity constructor
		@param _owners Array of addresses to associate with owner
		@param _threshold multisig threshold for owning authority
	 */
	constructor(
		address[] _owners,
		uint32 _threshold
	)
		MultiSig(_owners, _threshold)
		public 
	{
		/* First registrar is empty so Account.regKey == 0 means it is unset. */
		registrars.push(Contract(0, false));
	}

	/**
		@notice Fetch balance of an investor from their ID
		@param _id ID to query
		@return uint256 balance
	 */
	function balanceOf(bytes32 _id) external view returns (uint256) {
		return uint256(accounts[_id].balance);
	}

	/**
		@notice Fetch total investor counts and limits
		@return counts, limits
	 */
	function getInvestorCounts() external view returns (uint32[8], uint32[8]) {
		return (counts, limits);
	}

	/**
		@notice Fetch minrating, investor counts and limits of a country
		@dev counts[0] and levels[0] == the sum of counts[1:] and limits[1:]
		@param _country Country to query
		@return uint32 minRating, uint32 arrays of counts, limits
	 */
	function getCountry(
		uint16 _country
	)
		external
		view
		returns (uint32 _minRating, uint32[8] _count, uint32[8] _limit)
	{
		return (
			countries[_country].minRating,
			countries[_country].counts,
			countries[_country].limits
		);
	}

	/**
		@notice Set all information about a country
		@param _country Country to modify
		@param _allowed Is country approved
		@param _minRating minimum investor rating
		@param _limits array of investor limits
		@return bool success
	 */
	function setCountry(
		uint16 _country,
		bool _allowed,
		uint8 _minRating,
		uint32[8] _limits
	)
		external
		returns (bool)
	{
		if (!_checkMultiSig()) return false;
		Country storage c = countries[_country];
		c.limits = _limits;
		c.minRating = _minRating;
		c.allowed = _allowed;
		emit CountryModified(_country, _allowed, _minRating, _limits);
		return true;
	}

	/**
		@notice Initialize many countries in a single call
		@dev
			This call is useful if you have a lot of countries to approve
			where there is no investor limit specific to the investor ratings
		@param _country Array of counties to add
		@param _minRating Array of minimum investor ratings necessary for each country
		@param _limit Array of maximum mumber of investors allowed from this country
		@return bool success
	 */
	function setCountries(
		uint16[] _country,
		uint8[] _minRating,
		uint32[] _limit
	)
		external
		returns (bool)
	{
		require(_country.length == _minRating.length);
		require(_country.length == _limit.length);
		if (!_checkMultiSig()) return false;
		for (uint256 i = 0; i < _country.length; i++) {
			require(_minRating[i] != 0);
			Country storage c = countries[_country[i]];
			c.allowed = true;
			c.minRating = _minRating[i];
			c.limits[0] = _limit[i];
			emit CountryModified(_country[i], true, _minRating[i], c.limits);

		}
	}

	/**
		@notice Set investor limits
		@dev
			_limits[0] is the total investor limit, [1:] correspond to limits
			at each specific investor rating. Setting a value of 0 means there
			is no limit.
		@param _limits Array of limits
		@return bool success
	 */
	function setInvestorLimits(
		uint32[8] _limits
	)
		external
		returns (bool)
	{
		if (!_checkMultiSig()) return false;
		limits = _limits;
		emit InvestorLimitSet(0, _limits);
		return true;
	}

	/**
		@notice Check if transfer is possible based on issuer level restrictions
		@param _token address of token being transferred
		@param _auth address of the caller attempting the transfer
		@param _from address of the sender
		@param _to address of the receiver
		@param _value number of tokens being transferred
		@return bytes32 ID of caller
		@return bytes32[] IDs of sender and receiver
		@return uint8[] ratings of sender and receiver
		@return uint16[] countries of sender and receiver
	 */
	function checkTransfer(
		address _token,
		address _auth,
		address _from,
		address _to,
		uint256 _value
	)
		external
		returns (
			bytes32 _authID,
			bytes32[2] _id,
			uint8[2] _rating,
			uint16[2] _country
		)
	{
		_authID = _getID(_auth);
		_id[0] = _getID(_from);
		_id[1] = _getID(_to);
		
		if (_authID == ownerID && idMap[_auth].id != ownerID) {
			/*
				bytes4 signatures of transfer, transferFrom
				This enforces sub-authority permissioning around transfers
			*/
			require(
				authorityData[idMap[_auth].id].approvedUntil >= now &&
				authorityData[idMap[_auth].id].signatures[
					(_authID == _id[0] ? bytes4(0xa9059cbb) : bytes4(0x23b872dd))
				], "Authority is not permitted"
			);
		}

		address _addr = (_authID == _id[0] ? _auth : _from);
		bool[2] memory _allowed;

		(_allowed, _rating, _country) = _getInvestors(
			[_addr, _to],
			[accounts[idMap[_addr].id].regKey, accounts[idMap[_to].id].regKey]
		);
		_checkTransfer(_token, _authID, _id, _allowed, _rating, _country, _value);
		return (_authID, _id, _rating, _country);
	}	
		
	/**
		@notice View function to check if transfer is permitted
		@param _token address of token being transferred
		@param _from address of the sender
		@param _to address of the receiver
		@param _value number of tokens being transferred
		@return bytes32[] IDs of sender and receiver
		@return uint8[] ratings of sender and receiver
		@return uint16[] countries of sender and receiver
	 */
	function checkTransferView(
		address _token,
		address _from,
		address _to,
		uint256 _value
	)
		external
		view
		returns (
			bytes32[2] _id,
			uint8[2] _rating,
			uint16[2] _country
		)
	{	
		uint8[2] memory _key;
		(_id[0], _key[0]) = _getIDView(_from);
		(_id[1], _key[1]) = _getIDView(_to);

		if (_id[0] == ownerID && idMap[_from].id != ownerID) {
			require(
				authorityData[idMap[_from].id].approvedUntil >= now &&
				authorityData[idMap[_from].id].signatures[0xa9059cbb],
				"Authority is not permitted"
			);
		}

		address[2] memory _addr = [_from, _to];
		bool[2] memory _allowed;

		(_allowed, _rating, _country) = _getInvestors(_addr, _key);
		_checkTransfer(_token, _id[0], _id, _allowed, _rating, _country, _value);
		return (_id, _rating, _country);
	}

	/**
		@notice internal check if transfer is permitted
		@param _token address of token being transferred
		@param _authID id hash of caller
		@param _id addresses of sender and receiver
		@param _allowed array of permission bools from registrar
		@param _rating array of investor ratings
		@param _country array of investor countries
		@param _value amount to be transferred
	 */
	function _checkTransfer(
		address _token,
		bytes32 _authID,
		bytes32[2] _id,
		bool[2] _allowed,
		uint8[2] _rating,
		uint16[2] _country,
		uint256 _value
	)
		internal
		view
	{	
		require(tokens[_token].set);
		/* If issuer is not the authority, check the sender is not restricted */
		if (_authID != ownerID) {
			require(!locked, "Transfers locked: Issuer");
			require(!tokens[_token].restricted, "Transfers locked: Token");
			require(!accounts[_id[0]].restricted, "Sender restricted: Issuer");
			require(_allowed[0], "Sender restricted: Registrar");	
		}
		/* Always check the receiver is not restricted. */
		require(!accounts[_id[1]].restricted, "Receiver restricted: Issuer");
		require(_allowed[1], "Receiver restricted: Registrar");
		if (_id[0] != _id[1]) {
			/*
				A rating of 0 implies the receiver is the issuer or a
				custodian, no further checks are needed.
			*/
			if (_rating[1] != 0) {
				Country storage c = countries[_country[1]];
				require(c.allowed, "Reciever blocked: Country");
				/*  
					If the receiving investor currently has a 0 balance,
					we must make sure a slot is available for allocation.
				*/
				require(_rating[1] >= c.minRating, "Receiver blocked: Rating");
				if (accounts[_id[1]].balance == 0) {
					/* create a bool to prevent repeated comparisons */
					bool _check = (
						_rating[0] != 0 ||
						accounts[_id[1]].balance > _value
					);
					/*
						If the sender is an investor and still retains a balance,
						a new slot must be available.
					*/
					if (_check) {
						require(
							limits[0] == 0 ||
							counts[0] < limits[0],
							"Total Investor Limit"
						);
					}
					/*
						If the investors are from different countries, make sure
						a slot is available in the overall country limit.
					*/
					if (_check || _country[0] != _country[1]) {
						require(
							c.limits[0] == 0 ||
							c.counts[0] < c.limits[0],
							"Country Investor Limit"
						);
					}
					if (!_check) {
						_check = _rating[0] != _rating[1];
					}
					/*
						If the investors are of different ratings, make sure a
						slot is available in the receiver's rating in the overall
						count.
					*/
					if (_check) {
						require(
							limits[_rating[1]] == 0 ||
							counts[_rating[1]] < limits[_rating[1]],
							"Total Investor Limit: Rating"
						);
					}
					/*
						If the investors don't match in country or rating, make
						sure a slot is available in both the specific country
						and rating for the receiver.
					*/
					if (_check || _country[0] != _country[1]) {
						require(
							c.limits[_rating[1]] == 0 ||
							c.counts[_rating[1]] < c.limits[_rating[1]],
							"Country Investor Limit: Rating"
						);
					}
				}
			}
		}
		/* bytes4 signature for issuer module checkTransfer() */
		_callModules(0x47fca5df, abi.encode(
			_token,
			_authID,
			_id,
			_rating,
			_country,
			_value
		));
	}

	/**
		@notice External view to fetch an investor ID from an address
		@param _addr address of token being transferred
		@return bytes32 investor ID
	 */
	function getID(address _addr) external view returns (bytes32) {
		(bytes32 _id, uint8 _key) = _getIDView(_addr);
		return _id;
	}

	/**
		@notice internal investor ID fetch, updates local record
		@param _addr address of token being transferred
		@return bytes32 investor ID
	 */
	function _getID(address _addr) internal returns (bytes32) {
		(bytes32 _id, uint8 _key) = _getIDView(_addr);
		if (idMap[_addr].id == 0) {
			idMap[_addr].id = _id;
		}
		if (accounts[_id].regKey != _key) {
			accounts[_id].regKey = _key;
		}
		return _id;
	}

	/**
		@notice internal investor ID fetch
		@dev common logic for getID() and _getID()
		@param _addr address of token being transferred
		@return bytes32 investor ID, uint8 registrar index
	 */
	function _getIDView(address _addr) internal view returns (bytes32, uint8) {
		if (
			authorityData[idMap[_addr].id].addressCount > 0 ||
			_addr == address(this)
		) {
			return (ownerID, 0);
		}
		bytes32 _id = idMap[_addr].id;
		if (_id == 0) {
			for (uint256 i = 1; i < registrars.length; i++) {
				if (!registrars[i].restricted) {
					_id = KYCRegistrar(registrars[i].addr).getID(_addr);
					if (_id != 0) {
						return (_id, uint8(i));
					}
				}
			}
			revert("Address not registered");
		}
		if (custodians[_id].addr != 0) {
			return (_id, 0);
		}
		if (
			accounts[_id].regKey == 0 ||
			registrars[accounts[_id].regKey].restricted
		) {
			for (i = 1; i < registrars.length; i++) {
				if (
					!registrars[i].restricted && 
					_id == KYCRegistrar(registrars[i].addr).getID(_addr)
				) {
					return (_id, uint8(i));
				}
			}
			if (registrars[accounts[_id].regKey].restricted) {
				revert("Registrar restricted");
			}
			revert("Address not registered");
		}
		return (_id, accounts[_id].regKey);
	}

	/**
		@dev fetch investor data from registrar(s)
		@param _addr array of investor addresses
		@param _key array of registrar indexes
		@return permissions, ratings, and countries of investors
	 */
	function _getInvestors(
		address[2] _addr,
		uint8[2] _key
	)
		internal
		view
		returns (
			bool[2] _allowed,
			uint8[2] _rating,
			uint16[2] _country
		)
	{
		bytes32[2] memory _id;
		/* If key == 0 the address belongs to the issuer or a custodian. */
		if (_key[0] == 0) {
			_allowed[0] = true;
			_rating[0] = 0;
			_country[0] = 0;
		}
		if (_key[1] == 0) {
			_allowed[1] = true;
			_rating[1] = 0;
			_country[1] = 0;
		}
		/* If both investors are in the same registry, call getInvestors */
		if (_key[0] == _key[1] && _key[0] != 0) {
			(
				_id,
				_allowed,
				_rating,
				_country
			) = KYCRegistrar(registrars[_key[0]].addr).getInvestors(_addr[0], _addr[1]);
		/* Otherwise, call getInvestor at each registry */
		} else {
			if (_key[0] != 0) {
				(
					_id[0],
					_allowed[0],
					_rating[0],
					_country[0]
				) = KYCRegistrar(registrars[_key[0]].addr).getInvestor(_addr[0]);
			}
			if (_key[1] != 0) {
				(
					_id[1],
					_allowed[1],
					_rating[1],
					_country[1]
				) = KYCRegistrar(registrars[_key[1]].addr).getInvestor(_addr[1]);
			}	
		}
		return (_allowed, _rating, _country);
	}

	/**
		@notice Transfer tokens through the issuing entity level
		@param _id Array of sender/receiver IDs
		@param _rating Array of sender/receiver ratings
		@param _country Array of sender/receiver countries
		@param _value Number of tokens being transferred
		@return bool success
	 */
	function transferTokens(
		bytes32[2] _id,
		uint8[2] _rating,
		uint16[2] _country,
		uint256 _value
	)
		external
		onlyToken
		returns (bool)
	{
		/* custodian re-entrancy guard */
		require (!mutex);
		/* If no transfer of ownership, return true immediately */
		if (_id[0] == _id[1]) return true;
		/*
			If receiver is a custodian and sender is an investor, notify
			the custodian contract.
		*/
		if (custodians[_id[1]].addr != 0) {
			Custodian c = Custodian(custodians[_id[1]].addr);
			mutex = true;
			if (c.receiveTransfer(msg.sender, _id[0], _value) && _rating[0] > 0) {
				accounts[_id[0]].custodianCount = accounts[_id[0]].custodianCount.add(1);
				accounts[_id[0]].custodians[_id[1]] = true;
				emit BeneficialOwnerSet(address(c), _id[0], true);
			}
			mutex = false;
		}
		
		uint256 _balance = uint256(accounts[_id[0]].balance).sub(_value);
		_setBalance(_id[0], _rating[0], _country[0], _balance);
		_balance = uint256(accounts[_id[1]].balance).add(_value);
		_setBalance(_id[1], _rating[1], _country[1], _balance);
		/* bytes4 signature for token module transferTokens() */
		_callModules(0x0cfb54c9, abi.encode(
			msg.sender,
			_id, _rating,
			_country,
			_value
		));
		emit TransferOwnership(msg.sender, _id[0], _id[1], _value);
		
		return true;
	}

	/**
		@notice Affect a direct balance change (burn/mint) at the issuing entity level
		@dev This can only be called by a token
		@param _owner Token owner
		@param _old Old balance
		@param _new New balance
		@return id, rating, and country of the affected investor
	 */
	function modifyBalance(
		address _owner,
		uint256 _old,
		uint256 _new
	)
		external
		onlyToken
		returns (
			bytes32 _id,
			uint8 _rating,
			uint16 _country
		)
	{
		if (_owner == address(this)) {
			_id = ownerID;
			_rating = 0;
			_country = 0;
		} else {
			bool _allowed;
			uint8 _key = accounts[idMap[_owner].id].regKey;
			(
				_id,
				_allowed,
				_rating,
				_country
			) = KYCRegistrar(registrars[_key].addr).getInvestor(_owner);
		}
		uint256 _oldTotal = accounts[_id].balance;
		if (_new > _old) {
			uint256 _newTotal = uint256(accounts[_id].balance).add(_new.sub(_old));
		} else {
			_newTotal = uint256(accounts[_id].balance).sub(_old.sub(_new));
		}
		_setBalance(_id, _rating, _country, _newTotal);
		/* bytes4 signature for token module balanceChanged() */
		_callModules(0x4268353d, abi.encode(
			msg.sender,
			_id,
			_rating,
			_country,
			_oldTotal,
			_newTotal
		));
		return (_id, _rating, _country);
	}

	/**
		@notice Directly set a balance at the issuing entity level
		@param _id investor ID
		@param _rating investor rating
		@param _country investor country
		@param _value new balance value
	 */
	function _setBalance(
		bytes32 _id,
		uint8 _rating,
		uint16 _country,
		uint256 _value
	)
		internal
	{
		Account storage a = accounts[_id];
		Country storage c = countries[_country];
		if (_rating != 0) {
			/* rating from registrar does not match local rating */
			if (_rating != a.rating) {
				/* if local rating is not 0, rating has changed */
				if (a.rating > 0) {
					c.counts[_rating] = c.counts[_rating].sub(1);
					c.counts[a.rating] = c.counts[a.rating].add(1);
				}
				a.rating = _rating;
			}
			/* If investor account balance was 0, increase investor counts */
			if (a.balance == 0 && accounts[_id].custodianCount == 0) {
				_incrementCount(_rating, _country);
			/* If investor account balance is now 0, reduce investor counts */
			} else if (_value == 0 && accounts[_id].custodianCount == 0) {
				_decrementCount(_rating, _country);
			}
		}
		a.balance = uint192(_value);
		require(a.balance == _value);
	}

	/**
		@notice Increment investor count
		@param _r Investor rating
		@param _c Investor country
		@return bool success
	 */
	function _incrementCount(uint8 _r, uint16 _c) internal {
		counts[0] = counts[0].add(1);
		counts[_r] = counts[_r].add(1);
		countries[_c].counts[0] = countries[_c].counts[0].add(1);
		countries[_c].counts[_r] = countries[_c].counts[_r].add(1);
	}

	/**
		@notice Decrement investor count
		@param _r Investor rating
		@param _c Investor country
		@return bool success
	 */
	function _decrementCount(uint8 _r, uint16 _c) internal {
		counts[0] = counts[0].sub(1);
		counts[_r] = counts[_r].sub(1);
		countries[_c].counts[0] = countries[_c].counts[0].sub(1);
		countries[_c].counts[_r] = countries[_c].counts[_r].sub(1);
	}

	/**
		@notice Set document hash
		@param _documentID Document ID being hashed
		@param _hash Hash of the document
		@return bool success
	 */
	function setDocumentHash(
		string _documentID,
		bytes32 _hash
	)
		external
		returns (bool)
	{
		if (!_checkMultiSig()) return false;
		require(documentHashes[_documentID] == 0);
		documentHashes[_documentID] = _hash;
		emit NewDocumentHash(_documentID, _hash);
		return true;
	}

	/**
		@notice Fetch document hash
		@param _documentID Document ID to fetch
		@return document hash
	 */
	function getDocumentHash(string _documentID) external view returns (bytes32) {
		return documentHashes[_documentID];
	}

	/**
		@notice Attach or remove a KYCRegistrar contract
		@param _registrar address of registrar
		@param _allowed registrar permission
		@return bool success
	 */
	function setRegistrar(address _registrar, bool _allowed) external returns (bool) {
		if (!_checkMultiSig()) return false;
		for (uint256 i = 1; i < registrars.length; i++) {
			if (registrars[i].addr == _registrar) {
				registrars[i].restricted = !_allowed;
				emit RegistrarSet(_registrar, _allowed);
				return true;
			}
		}
		if (_allowed) {
			registrars.push(Contract(_registrar, false));
			emit RegistrarSet(_registrar, _allowed);
			return true;
		}
		revert();		
	}

	/**
		@notice Get address of the registrar an investor is associated with
		@param _id Investor ID
		@return registrar address
	 */
	function getInvestorRegistrar(bytes32 _id) external view returns (address) {
		return registrars[accounts[_id].regKey].addr;
	}

	/**
		@notice Add a custodian
		@dev
			Custodians are entities such as broker or exchanges that are approved
			to hold tokens for 1 or more beneficial owners.
			https://sft-protocol.readthedocs.io/en/latest/custodian.html
		@param _custodian address of custodian contract
		@return bool success
	 */
	function addCustodian(address _custodian) external returns (bool) {
		if (!_checkMultiSig()) return false;
		bytes32 _id = Custodian(_custodian).ownerID();
		idMap[_custodian].id = _id;
		custodians[_id].addr = _custodian;
		emit CustodianAdded(_custodian);
		return true;
	}

	/**
		@notice Add a new security token contract
		@param _token Token contract address
		@return bool success
	 */
	function addToken(address _token) external returns (bool) {
		if (!_checkMultiSig()) return false;
		SecurityToken token = SecurityToken(_token);
		require(!tokens[_token].set);
		require(token.ownerID() == ownerID);
		require(token.circulatingSupply() == 0);
		tokens[_token].set = true;
		uint256 _balance = uint256(accounts[ownerID].balance).add(token.treasurySupply());
		accounts[ownerID].balance = uint192(_balance);
		require(accounts[ownerID].balance == _balance);
		emit TokenAdded(_token);
		return true;
	}

	/**
		@notice Set restriction on an investor ID
		@dev
			This is used for regular investors or custodians. Restrictions
			on sub-authorities must be handled with MultiSig functions.
		@param _id investor ID
		@param _allowed permission bool
		@return bool success
	 */
	function setInvestorRestriction(
		bytes32 _id,
		bool _allowed
	)
		external
		returns (bool)
	{
		if (!_checkMultiSig()) return false;
		accounts[_id].restricted = !_allowed;
		emit InvestorRestriction(_id, _allowed);
		return true;
	}

	/**
		@notice Set restriction on a token
		@dev
			Only the issuer can transfer restricted tokens. Useful in dealing
			with a security breach or a token migration.
		@param _token Address of the token
		@param _allowed permission bool
		@return bool success
	 */
	function setTokenRestriction(
		address _token,
		bool _allowed
	)
		external
		returns (bool)
	{
		if (!_checkMultiSig()) return false;
		require(tokens[_token].set);
		tokens[_token].restricted = !_allowed;
		emit TokenRestriction(_token, _allowed);
		return true;
	}

	/**
		@notice Set restriction on all tokens for this issuer
		@dev Only the issuer can transfer restricted tokens.
		@param _allowed permission bool
		@return bool success
	 */
	function setGlobalRestriction(bool _allowed) external returns (bool) {
		if (!_checkMultiSig()) return false;
		locked = !_allowed;
		emit GlobalRestriction(_allowed);
		return true;
	}

	/**
		@notice Attach a module to IssuingEntity or SecurityToken
		@dev
			Modules have a lot of permission and flexibility in what they
			can do. Only attach a module that has been properly auditted and
			where you understand exactly what it is doing.
			https://sft-protocol.readthedocs.io/en/latest/modules.html
		@param _target Address of the contract where the module is attached
		@param _module Address of the module contract
		@return bool success
	 */
	function attachModule(
		address _target,
		address _module
	)
		external
		returns (bool)
	{
		if (!_checkMultiSig()) return false;
		if (_target == address(this)) {
			_attachModule(_module);
		} else {
			require(tokens[_target].set);
			SecurityToken(_target).attachModule(_module);
		}
		return true;
	}

	/**
		@notice Detach a module from IssuingEntity or SecurityToken
		@dev This function may also be called by the module itself.
		@param _target Address of the contract where the module is attached
		@param _module Address of the module contract
		@return bool success
	 */
	function detachModule(
		address _target,
		address _module
	)
		external
		returns (bool)
	{
		if (_module != msg.sender) {
			if (!_checkMultiSig()) return false;
		}
		if (_target == address(this)) {
			_detachModule(_module);
		} else {
			require(tokens[_target].set);
			SecurityToken(_target).detachModule(_module);
		}
		return true;
	}

	/**
		@notice Add or remove an investor from a custodian's beneficial owners
		@dev Only callable by a custodian or the issuer
		@param _custID Custodian ID
		@param _id Array of investor IDs
		@param _add bool add or remove
		@return bool success
	 */
	function setBeneficialOwners(
		bytes32 _custID,
		bytes32[] _id,
		bool _add
	)
		external
		returns (bool)
	{
		/* custodian re-entrancy guard */
		require (!mutex);
		if (custodians[_custID].addr != msg.sender) {
			if (!_checkMultiSig()) return false;
		}
		for (uint256 i = 0; i < _id.length; i++) {
			if (_id[i] == 0) continue;
			if (_id[i] == ownerID || custodians[_id[i]].addr != 0) continue;
			Account storage a = accounts[_id[i]];
			if (a.custodians[_custID] == _add) continue;
			a.custodians[_custID] = _add;
			emit BeneficialOwnerSet(msg.sender, _id[i], _add);
			if (_add) {
				a.custodianCount = a.custodianCount.add(1);
				if (a.custodianCount == 1 && a.balance == 0) {
					_incrementCount(
						a.rating,
						KYCRegistrar(registrars[a.regKey].addr).getCountry(_id[i])
					);	
				}
			} else {
				a.custodianCount = a.custodianCount.sub(1);
				if (a.custodianCount == 0 && a.balance == 0) {
					_decrementCount(
						a.rating,
						KYCRegistrar(registrars[a.regKey].addr).getCountry(_id[i])
					);	
				}
			}
		}
		return true;
	}

	
}