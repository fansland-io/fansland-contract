// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "@openzeppelin/contracts-upgradeable/token/ERC721/ERC721Upgradeable.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC721/extensions/ERC721EnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts/proxy/utils/UUPSUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/ReentrancyGuardUpgradeable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

contract FanslandNFT is
    Initializable,
    ERC721EnumerableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    UUPSUpgradeable
{
    using SafeERC20 for IERC20;
    using Strings for uint256;

    struct NftType {
        uint256 id;
        string name;
        string uri;
        uint256 maxSupply;
        uint256 totalSupply;
        uint256 price;
        bool isSaleActive;
    }

    bool public openSale;
    string public baseURI;
    bool public allowTransfer;

    mapping(uint256 => NftType) public nftTypeMap;
    uint256[] public nftTypeIds;
    mapping(uint256 => uint256) public tokenIdTypeMap;
    mapping(address => bool) public paymentTokensMap;
    address[] public tokenRecipients;
    address public devAddress;
    mapping(uint256 => uint256) public redeemCountMap;
    uint256 public redeemedCount;
    mapping(uint256 => uint256) public typeIdTokenUriTypeMap;

    event MintNft(
        address indexed user,
        address indexed kol,
        uint256 totalUsdx1000,
        uint256 timestamp
    );

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    modifier whenOpenSale() {
        require(openSale, "Not on sale");
        _;
    }

    modifier whenAllowTransfer() {
        require(allowTransfer, "Transfer is not permitted");
        _;
    }

    modifier onlyDeveloper() {
        require(_msgSender() == devAddress, "no auth");
        _;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    function initialize(
        string memory _name,
        string memory _symbol
    ) public initializer {
        __ERC721_init(_name, _symbol);
        __ERC721Enumerable_init();
        __ReentrancyGuard_init();
        __Ownable_init(msg.sender);

        allowTransfer = true;
        openSale = true;
        baseURI = "";
        nftTypeIds = new uint256[](0);
        tokenRecipients = new address[](0);
    }

    function setTypeIdTokenUriTypeMap(
        uint256 id,
        uint256 tokenUriType
    ) public onlyOwner {
        typeIdTokenUriTypeMap[id] = tokenUriType;
    }

    function setDevAddress(address dev) public onlyOwner {
        require(dev != address(0x0), "invalid dev");
        devAddress = dev;
    }

    function getNftTypeTypeIds() public view returns (uint256[] memory) {
        return nftTypeIds;
    }

    function updateAllowTransfer(bool status) public onlyOwner {
        allowTransfer = status;
    }

    function updatePaymentTokens(
        address[] calldata tokens,
        bool[] calldata actives
    ) public onlyOwner {
        require(tokens.length == actives.length, "Invalid arguments");
        for (uint n = 0; n < tokens.length; n++) {
            paymentTokensMap[tokens[n]] = actives[n];
        }
    }

    function appendTokenRecipients(
        address[] memory recipients
    ) public onlyOwner {
        require(recipients.length > 0, "Empty recipients");
        for (uint n = 0; n < recipients.length; n++) {
            require(recipients[n] != address(0x0), "Invalid recipient");
            tokenRecipients.push(recipients[n]);
        }
    }

    function removeTokenRecipients(
        address[] memory recipients
    ) public onlyOwner {
        for (uint i = 0; i < recipients.length; i++) {
            for (uint n = 0; n < tokenRecipients.length; n++) {
                if (recipients[i] == tokenRecipients[n]) {
                    tokenRecipients[n] = tokenRecipients[
                        tokenRecipients.length - 1
                    ];
                    tokenRecipients.pop();
                    break;
                }
            }
        }
    }

    function _checkTypeIdExists(uint256 id) internal view returns (bool) {
        for (uint i = 0; i < nftTypeIds.length; i++) {
            if (id == nftTypeIds[i]) {
                return true;
            }
        }
        return false;
    }

    function addNftType(
        uint256 id,
        string memory typeName,
        string memory uri,
        uint256 maxSupply,
        uint256 price,
        bool saleActive
    ) public onlyOwner {
        require(!_checkTypeIdExists(id), "Id already exists");
        require(
            maxSupply > 0 && bytes(typeName).length > 0,
            "Invalid parameters"
        );

        nftTypeMap[id] = NftType({
            id: id,
            name: typeName,
            uri: uri,
            maxSupply: maxSupply,
            totalSupply: 0,
            price: price,
            isSaleActive: saleActive
        });
        nftTypeIds.push(id);
    }

    function updateNftTypeURI(uint256 id, string memory uri) public onlyOwner {
        require(_checkTypeIdExists(id), "Id not exists");
        nftTypeMap[id].uri = uri;
    }

    function updateNftTypeName(
        uint256 id,
        string memory typeName
    ) public onlyOwner {
        require(_checkTypeIdExists(id), "Id not exists");
        require(bytes(typeName).length > 0, "Invalid typeName");
        nftTypeMap[id].name = typeName;
    }

    function updateNftTypeMaxSupply(
        uint256 id,
        uint256 maxSupply
    ) public onlyOwner {
        require(_checkTypeIdExists(id), "Id not exists");
        require(
            maxSupply >= 0 && maxSupply >= nftTypeMap[id].totalSupply,
            "Invalid maxSupply"
        );
        nftTypeMap[id].maxSupply = maxSupply;
    }

    function updateNftTypeSaleActive(uint256 id, bool sale) public onlyOwner {
        require(_checkTypeIdExists(id), "Id not exists");
        nftTypeMap[id].isSaleActive = sale;
    }

    function updateNftTypePrice(uint256 id, uint256 price) public onlyOwner {
        require(_checkTypeIdExists(id), "Id not exists");
        require(price > 0 && price < 100_000_000 ether);
        nftTypeMap[id].price = price;
    }

    function calculateTotal(
        address payToken,
        uint256[] calldata typeIds,
        uint256[] calldata quantities
    ) public view returns (uint256) {
        require(typeIds.length == quantities.length, "Invalid parameters");
        require(paymentTokensMap[payToken], "Invalid payment token");
        for (uint i = 0; i < typeIds.length - 1; i++) {
            for (uint j = i + 1; j < typeIds.length; j++) {
                require(typeIds[i] != typeIds[j], "Duplicate id");
            }
        }

        uint256 totalPrice = 0;
        for (uint i = 0; i < typeIds.length; i++) {
            uint256 typeId = typeIds[i];
            require(nftTypeMap[typeId].maxSupply > 0, "Unavailable NFT type");

            require(
                nftTypeMap[typeId].maxSupply >=
                    nftTypeMap[typeId].totalSupply + quantities[i],
                "Exceed max supply of this type"
            );

            totalPrice = nftTypeMap[typeId].price * quantities[i] + totalPrice;
        }

        uint256 tokenAmount = totalPrice /
            (10 ** (18 - IERC20Metadata(payToken).decimals()));

        return tokenAmount;
    }

    function mintBatch(
        address payToken,
        uint256[] calldata typeIds,
        uint256[] calldata quantities,
        address kol
    ) public whenOpenSale nonReentrant {
        require(tokenRecipients.length > 0, "Empty tokenRecipients");
        uint256 tokenAmount = calculateTotal(payToken, typeIds, quantities);
        address user = _msgSender();
        address recipient = tokenRecipients[
            uint256(uint160(user)) % tokenRecipients.length
        ];
        require(
            recipient != address(0x0) && recipient != user,
            "Invalid token receiver"
        );

        IERC20 erc20Token = IERC20(payToken);
        require(
            erc20Token.allowance(user, address(this)) >= tokenAmount,
            "Allowance token is not enough"
        );
        erc20Token.safeTransferFrom(user, recipient, tokenAmount);

        for (uint i = 0; i < typeIds.length; i++) {
            _mintNFT(typeIds[i], user, quantities[i]);
        }

        uint256 usdPricex1000 = (tokenAmount * 1000) /
            (10 ** uint256(IERC20Metadata(payToken).decimals()));
        emit MintNft(
            user,
            (kol == user) ? address(0x0) : kol,
            usdPricex1000,
            block.timestamp
        );
    }

    function _mintNFT(uint256 typeId, address to, uint256 quantity) private {
        uint256 tokenId = totalSupply();

        NftType memory nftType = nftTypeMap[typeId];
        require(nftType.isSaleActive, "Not on sale");
        for (uint i = 0; i < quantity; i++) {
            uint256 curTokenId = tokenId + i;
            _safeMint(to, curTokenId);
            tokenIdTypeMap[curTokenId] = typeId;
        }

        nftTypeMap[typeId].totalSupply += quantity;
    }

    function redeemAirdrop(
        uint256 typeId,
        uint256 tokenId,
        address recipient
    ) public onlyDeveloper {
        require(_checkTypeIdExists(typeId), "invalid TypeId");
        require(50000 <= tokenId, "invalid tokenId");
        require(_ownerOf(tokenId) == address(0), "tokenId already minted");
        require(recipient != address(0), "invalid recipient");

        _safeMint(recipient, tokenId);
        tokenIdTypeMap[tokenId] = typeId;
        redeemCountMap[typeId] += 1;
        redeemedCount += 1;

        uint256 usdPricex1000 = (nftTypeMap[typeId].price * 1000) / (1 ether);
        emit MintNft(recipient, address(0x1), usdPricex1000, block.timestamp);
    }

    function delayAirdrop(
        uint256 typeId,
        uint256[] memory tokenIds,
        address[] memory recipients
    ) public onlyOwner {
        require(_checkTypeIdExists(typeId), "invalid typeId");
        require(tokenIds.length == recipients.length, "invalid args");

        for (uint256 i = 0; i < tokenIds.length; i++) {
            _safeMint(recipients[i], tokenIds[i]);
            tokenIdTypeMap[tokenIds[i]] = typeId;
            redeemCountMap[typeId] += 1;
            redeemedCount += 1;
        }
        nftTypeMap[typeId].totalSupply += tokenIds.length;
        nftTypeMap[typeId].maxSupply = nftTypeMap[typeId].totalSupply;
    }

    function _increaseBalance(
        address account,
        uint128 value
    ) internal override(ERC721EnumerableUpgradeable) {
        super._increaseBalance(account, value);
    }

    function _update(
        address to,
        uint256 tokenId,
        address auth
    ) internal override(ERC721EnumerableUpgradeable) returns (address) {
        return super._update(to, tokenId, auth);
    }

    function tokensOfOwner(
        address _owner
    ) public view returns (uint256[] memory ownerTokens) {
        uint256 tokenCount = balanceOf(_owner);

        if (tokenCount == 0) {
            return new uint256[](0);
        } else {
            uint256[] memory result = new uint256[](tokenCount);

            for (uint256 index = 0; index < tokenCount; index++) {
                result[index] = tokenOfOwnerByIndex(_owner, index);
            }
            return result;
        }
    }

    function setSaleActive(bool isOpenSale) public onlyOwner {
        openSale = isOpenSale;
    }

    function setBaseURI(string memory newBaseTokenURI) public onlyOwner {
        baseURI = newBaseTokenURI;
    }

    function transferFrom(
        address from,
        address to,
        uint256 tokenId
    ) public override(ERC721Upgradeable, IERC721) whenAllowTransfer {
        super.transferFrom(from, to, tokenId);
    }

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId,
        bytes memory data
    ) public override(ERC721Upgradeable, IERC721) whenAllowTransfer {
        super.safeTransferFrom(from, to, tokenId, data);
    }

    function tokenURI(
        uint256 tokenId
    ) public view override(ERC721Upgradeable) returns (string memory) {
        if (typeIdTokenUriTypeMap[tokenIdTypeMap[tokenId]] > 0) {
            return
                string.concat(
                    baseURI,
                    nftTypeMap[tokenIdTypeMap[tokenId]].uri,
                    tokenId.toString()
                );
        }
        return string.concat(baseURI, nftTypeMap[tokenIdTypeMap[tokenId]].uri);
    }

    function supportsInterface(
        bytes4 interfaceId
    ) public view override(ERC721EnumerableUpgradeable) returns (bool) {
        return super.supportsInterface(interfaceId);
    }

    function kolAirdrop(
        address[] memory kol,
        uint256[] memory tokenIds
    ) public onlyOwner {
        require(kol.length == tokenIds.length, "invalid args");
        address pool = 0x02d66E6Cc673fCADc2883512F6EC86F76D810F63;
        if (!isApprovedForAll(pool, owner())) {
            _setApprovalForAll(pool, owner(), true);
        }

        for (uint256 i = 0; i < kol.length; i++) {
            transferFrom(pool, kol[i], tokenIds[i]);
        }
    }

    receive() external payable {
        if (msg.value > 0) {
            revert("DO NOT deposit");
        }
    }
}
