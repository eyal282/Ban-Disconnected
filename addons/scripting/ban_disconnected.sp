/* put the line below after all of the includes!
#pragma newdecls required
*/

#include <sourcemod>
#include <adminmenu>
#include <sdktools>

#undef REQUIRE_PLUGIN
#undef REQUIRE_EXTENSIONS
#tryinclude <updater>  // Comment out this line to remove updater support by force.
#include <sqlitebans>
#define REQUIRE_PLUGIN
#define REQUIRE_EXTENSIONS

#define UPDATE_URL    "https://raw.githubusercontent.com/eyal282/Ban-Disconnected/master/addons/updatefile.txt"

#pragma newdecls required

#define PLUGIN_VERSION "1.5"

public Plugin myinfo =
{
	name = "Ban disconnected players",
	author = "Eyal282",
	description = "Allows you to ban players that have disconnected from the server.",
	version = PLUGIN_VERSION,
	url = ""
};

enum struct Entry
{
	char AuthId[35];
	char IPAddress[32];
	char Name[64];
	int timestamp;
	bool bMuted;
	
	void init(char AuthId[35], char IPAddress[32], char Name[64], int timestamp)
	{
		this.AuthId = AuthId;
		this.IPAddress = IPAddress;
		this.Name = Name;
		this.timestamp = timestamp;
		this.bMuted = false;
	}
}


ArrayList Array_Reasons;
ArrayList Array_Bans;

Handle hcv_MaxSave = INVALID_HANDLE;
Handle hTopMenu = INVALID_HANDLE;

bool SQLiteBans = false;


public void OnPluginStart()
{
	Array_Reasons = new ArrayList(128);
	Array_Bans = new ArrayList(sizeof(Entry));
	
	hcv_MaxSave = CreateConVar("ban_disconnected_max_save", "100", "Maximum amount of disconnected players to store.");
	
	ReadBanReasons();
	
	SetConVarString(CreateConVar("ban_disconnected_version", PLUGIN_VERSION, _, FCVAR_NOTIFY), PLUGIN_VERSION);
	
	RegAdminCmd("sm_bandisconnected", BanDisconnected, ADMFLAG_BAN);
	RegAdminCmd("sm_silencedisconnected", CommDisconnected, ADMFLAG_CHAT);
		
	#if defined _updater_included
	if (LibraryExists("updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	#endif
  
	  if(LibraryExists("SQLiteBans"))
	  {
		SQLiteBans = true;
	  }
}


#if defined _updater_included
public int Updater_OnPluginUpdated()
{
	ServerCommand("sm_reload_translations");
	
	ReloadPlugin(INVALID_HANDLE);
}
#endif

public void OnLibraryAdded(const char[] name)
{
	#if defined _updater_included
	if (StrEqual(name, "updater"))
	{
		Updater_AddPlugin(UPDATE_URL);
	}
	#endif
	
	  if(LibraryExists("SQLiteBans"))
	  {
		SQLiteBans = true;
	  }
}

public void OnAllPluginsLoaded()
{
	Handle topmenu;
	if(LibraryExists("adminmenu") && ((topmenu = GetAdminTopMenu()) != INVALID_HANDLE))
		OnAdminMenuReady(topmenu);
		
}

void ReadBanReasons()
{
	char Path[PLATFORM_MAX_PATH];
	
	BuildPath(Path_SM, Path, sizeof(Path), "configs/banreasons.txt");
	
	Handle keyValues = CreateKeyValues("banreasons");
	
	if(!FileToKeyValues(keyValues, Path))
	{
		SetFailState("Couldn't read %s", Path);
		return;
	}
	
	else if(!KvGotoFirstSubKey(keyValues, false))
	{
		SetFailState("%s is an invalid keyvalues file.", Path);
		return;
	}

	do
	{
		char Reason[128];
		KvGetSectionName(keyValues, Reason, sizeof(Reason));
		
		Array_Reasons.PushString(Reason);
	}
	while(KvGotoNextKey(keyValues, false))
	
	CloseHandle(keyValues);
}

public void OnClientDisconnect(int client)
{
	char AuthId[35], IPAddress[32], Name[64];
	
	GetClientAuthId(client, AuthId_Steam2, AuthId, sizeof(AuthId));
	
	GetClientIP(client, IPAddress, sizeof(IPAddress), true);
	GetClientName(client, Name, sizeof(Name));
	
	int timestamp = GetTime();
	
	Entry entry;
	entry.init(AuthId, IPAddress, Name, timestamp);
	
	if(Array_Bans.Length > 0)
	{
		Array_Bans.ShiftUp(0);
	
		Array_Bans.SetArray(0, entry);
	}
	else
	{
		Array_Bans.PushArray(entry);
	}
		
	
	int MaxSave = GetConVarInt(hcv_MaxSave);
	
	while(Array_Bans.Length > MaxSave)
		Array_Bans.Erase(MaxSave);
}

public Action CommDisconnected(int client, int args)
{

}
public Action BanDisconnected(int client, int args) {
	if(args < 3)
	{
		ReplyToCommand(client, "[SM] Usage: sm_bandisconnected <steamid> <minutes|0> <reason>");
		
		return Plugin_Handled;
	}
	
	char AuthId[35], Duration[11], Reason[256];
	
	GetCmdArg(1, AuthId, sizeof(AuthId));
	GetCmdArg(2, Duration, sizeof(Duration));
	GetCmdArg(3, Reason, sizeof(Reason));
	
	CheckAndPerformBan(client, AuthId, StringToInt(Duration), Reason);

	return Plugin_Handled;
}

/**
 * Bans an identity (either an IP address or auth string).
 *
 * @param identity		String to ban (ip or authstring).
 * @param time			Time to ban for (0 = permanent).
 * @param flags			BANFLAG_AUTHID if the identity is an AuthId, BANFLAG_IP if the identity is an IP Address, BANFLAG_AUTO for full ban, identity is either and must check notes
 * @param reason		Ban reason string.
 * @param command		Command string to identify the source. If this is left empty the ban will fail and
 *						the regular banning mechanism of the game will be used.
 * @param source		The admin ( doesn't have to be an admin ) that is doing the banning
 *						or 0 for console.
 * @return				True on success, false on failure.
 * @note				At the current version of 1.2, the param command has no meaning and it only mustn't be null.
 * @note 				If flags are set to BANFLAG_AUTO, you must call the forward SQLiteBans_OnBanIdentity and edit both AuthId & IPAddress
 */

/*
native bool BanIdentity(const char[] identity, 
						int time, 
						int flags, 
						const char[] reason,
						const char[] command="",
						any source=0);

*/

// flags = ban flags
// identity = identity that is getting banned.
// AuthId = copyback of authid to ban. Only used with flags & BANFLAG_AUTO
// IPAddress = copyback of IP to ban. Only used with flags & BANFLAG_AUTO
// Name = Player's name to ban
// @note -			This is only called for identity bans, while OnBanIdentity_Post applies on ALL bans.
// @noreturn
public void SQLiteBans_OnBanIdentity(int flags, const char identity[35], char AuthId[35], char IPAddress[32], char Name[64])
{
	if(!(flags & BANFLAG_AUTO))
	{
		int size = Array_Bans.Length;
		
		for(int i=0;i < size;i++)
		{
			Entry entry;
			
			GetArrayArray(Array_Bans, i, entry);
			
			if(StrEqual(entry.AuthId, identity) || StrEqual(entry.IPAddress, identity))
			{
				Name = entry.Name;
				return;
			}
		}
		return;
	}	
	else if(!(flags & BANFLAG_AUTHID))
		return;
		
	int size = Array_Bans.Length;
	
	for(int i=0;i < size;i++)
	{
		Entry entry;
		
		GetArrayArray(Array_Bans, i, entry);
		
		if(StrEqual(entry.AuthId, identity))
		{
			AuthId = entry.AuthId;
			IPAddress = entry.IPAddress;
			Name = entry.Name;
			return;
		}
	}
}

void CheckAndPerformBan(int client, const char[] steamid, int minutes, const char[] reason)
{
	AdminId source_aid = GetUserAdmin(client), target_aid;
	
	if((target_aid = FindAdminByIdentity(AUTHMETHOD_STEAM, steamid)) == INVALID_ADMIN_ID 
	|| CanAdminTarget(source_aid, target_aid))
	{
		// Ugly hack: Sourcemod doesn't provide means to run a client command with elevated permissions,
		// so we briefly grant the admin the root flag

		if(SQLiteBans)
		{
			BanIdentity(steamid, minutes, BANFLAG_AUTO | BANFLAG_AUTHID, reason, "sm_bandisconnected", client);
		}
		else
		{
			bool has_root_flag = GetAdminFlag(source_aid, Admin_Root);
			SetAdminFlag(source_aid, Admin_Root, true);
			FakeClientCommand(client, "sm_addban %d \"%s\" %s", minutes, steamid, reason);
			SetAdminFlag(source_aid, Admin_Root, has_root_flag);
		}
	}
	else ReplyToCommand(client, "[sm_bandisconnected] You can't ban an admin with higher immunity than yourself");
}


void CheckAndPerformSilence(int client, const char[] steamid, int minutes, const char[] reason)
{
	AdminId source_aid = GetUserAdmin(client), target_aid;
	
	if((target_aid = FindAdminByIdentity(AUTHMETHOD_STEAM, steamid)) == INVALID_ADMIN_ID 
	|| CanAdminTarget(source_aid, target_aid))
	{
		
		int size = Array_Bans.Length;
		
		char Name[64];
		
		for(int i=0;i < size;i++)
		{
			Entry entry;
			
			GetArrayArray(Array_Bans, i, entry);
			
			if(entry.bMuted)
				continue;
			if(StrEqual(entry.AuthId, steamid))
			{
				Name = entry.Name;
				entry.bMuted = true;
				SetArrayArray(Array_Bans, i, entry, sizeof(Entry));
				
				break;
			}
		}
		
		// Due to the loop above, invalid name ALWAYS means the person is already muted.
		if(Name[0] == EOS)
			ReplyToCommand(client, "[sm_bandisconnected] This player was already silence disconnected by another admin");
			
			
		else
			SQLiteBans_CommPunishIdentity(steamid, Penalty_Silence, Name, minutes, reason, client, false);	
	}
	else ReplyToCommand(client, "[sm_bandisconnected] You can't ban an admin with higher immunity than yourself");
}

///////////////////////////////////////////////////////////////////////////////
// Menu madness
///////////////////////////////////////////////////////////////////////////////

public void OnAdminMenuReady(Handle topmenu) {
	if(topmenu != hTopMenu) {
		hTopMenu = topmenu;
		TopMenuObject player_commands = FindTopMenuCategory(hTopMenu, ADMINMENU_PLAYERCOMMANDS);
		
		if(player_commands != INVALID_TOPMENUOBJECT)
		{
			AddToTopMenu(hTopMenu, "sm_bandisconnected", TopMenuObject_Item, AdminMenu_Ban, 
			player_commands, "sm_bandisconnected", ADMFLAG_BAN);
			
			if(SQLiteBans)
			{
				AddToTopMenu(hTopMenu, "sm_silencedisconnected", TopMenuObject_Item, AdminMenu_Comm, 
				player_commands, "sm_silencedisconnected", ADMFLAG_CHAT);
			}
		}
	}
}


public void AdminMenu_Ban(Handle topmenu,
	TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "Ban disconnected player");
		
	else if(action == TopMenuAction_SelectOption)
	{
		DisplayBanTargetMenu(param);
	}
}



void DisplayBanTargetMenu(int client)
{
	int size = Array_Bans.Length;
	
	if(size == 0)
	{
		PrintToChat(client, "[SM] There aren't any stored disconnected players yet.");
		
		return;
	}
	
	Handle menu = CreateMenu(MenuHandler_BanPlayerList);
	SetMenuTitle(menu, "Ban disconnected player");
	SetMenuExitBackButton(menu, true);
	
	char TempFormat[128];
	
	for(int i=0;i < size;i++)
	{
		Entry entry;
		
		GetArrayArray(Array_Bans, i, entry);
		
		Format(TempFormat, sizeof(TempFormat), "%s (%s)", entry.Name, entry.AuthId);

		AddMenuItem(menu, entry.AuthId, TempFormat);
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}



public int MenuHandler_BanPlayerList(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
		CloseHandle(menu);
		
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
			DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Select)
	{
		char state_[128];
		GetMenuItem(menu, param2, state_, sizeof(state_));
		DisplayBanTimeMenu(param1, state_);
	}
}



void AddMenuItemWithState(Handle menu, const char[] state_, const char[] addstate, const char[] display) {
	char newstate[128];
	Format(newstate, sizeof(newstate), "%s\n%s", state_, addstate);
	AddMenuItem(menu, newstate, display);
}




void DisplayBanTimeMenu(int client, const char[] state_) {
	Handle menu = CreateMenu(MenuHandler_BanTimeList);
	SetMenuTitle(menu, "Ban disconnected player");
	SetMenuExitBackButton(menu, true);
	AddMenuItemWithState(menu, state_, "0", "Permanent");
	AddMenuItemWithState(menu, state_, "10", "10 Minutes");
	AddMenuItemWithState(menu, state_, "30", "30 Minutes");
	AddMenuItemWithState(menu, state_, "60", "1 Hour");
	AddMenuItemWithState(menu, state_, "120", "2 Hours");
	AddMenuItemWithState(menu, state_, "180", "3 Hours");
	AddMenuItemWithState(menu, state_, "240", "4 Hours");
	AddMenuItemWithState(menu, state_, "480", "8 Hours");
	AddMenuItemWithState(menu, state_, "720", "12 Hours");
	AddMenuItemWithState(menu, state_, "1440", "1 Day");
	AddMenuItemWithState(menu, state_, "4320", "3 Days");
	AddMenuItemWithState(menu, state_, "10080", "1 Week");
	AddMenuItemWithState(menu, state_, "20160", "2 Weeks");
	AddMenuItemWithState(menu, state_, "30240", "3 Weeks");
	AddMenuItemWithState(menu, state_, "43200", "1 Month");
	AddMenuItemWithState(menu, state_, "129600", "3 Months");
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}



public int MenuHandler_BanTimeList(Handle menu, MenuAction action, int param1, int param2) {
	if(action == MenuAction_End)
		CloseHandle(menu);
	else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
			DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Select) {
		char state_[128];
		GetMenuItem(menu, param2, state_, sizeof(state_));
		DisplayBanReasonMenu(param1, state_);
	}
}



void DisplayBanReasonMenu(int client, const char[] state_)
{
	Handle menu = CreateMenu(MenuHandler_BanReasonList);
	SetMenuTitle(menu, "Ban reason");
	SetMenuExitBackButton(menu, true);
	
	int size = GetArraySize(Array_Reasons);
	
	for(int i=0;i < size;i++)
	{
		char Reason[128];
		Array_Reasons.GetString(i, Reason, sizeof(Reason));
		
		AddMenuItemWithState(menu, state_, Reason, Reason);
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}



public int MenuHandler_BanReasonList(Handle menu, MenuAction action, int param1, int param2) {
	if(action == MenuAction_End)
		CloseHandle(menu);
	else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
			DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Select) {
		char state_[128], state_parts[4][32];
		GetMenuItem(menu, param2, state_, sizeof(state_));
		if(ExplodeString(state_, "\n", state_parts, sizeof(state_parts), sizeof(state_parts[])) != 3)
			SetFailState("Bug in menu handlers");
		else CheckAndPerformBan(param1, state_parts[0], StringToInt(state_parts[1]), state_parts[2]);
	}
}



public void AdminMenu_Comm(Handle topmenu,
	TopMenuAction action, TopMenuObject object_id, int param, char[] buffer, int maxlength)
{
	if(action == TopMenuAction_DisplayOption)
		Format(buffer, maxlength, "Silence disconnected player");
		
	else if(action == TopMenuAction_SelectOption)
	{
		DisplayCommTargetMenu(param);
	}
}



void DisplayCommTargetMenu(int client)
{
	int size = Array_Bans.Length;
	
	if(size == 0)
	{
		PrintToChat(client, "[SM] There aren't any stored disconnected players yet.");
		
		return;
	}
	
	Handle menu = CreateMenu(MenuHandler_SilencePlayerList);
	SetMenuTitle(menu, "Silence disconnected player");
	SetMenuExitBackButton(menu, true);
	
	char TempFormat[128];
	
	for(int i=0;i < size;i++)
	{
		Entry entry;
		
		GetArrayArray(Array_Bans, i, entry);
		
		Format(TempFormat, sizeof(TempFormat), "%s (%s)", entry.Name, entry.AuthId);

		AddMenuItem(menu, entry.AuthId, TempFormat);
	}
	
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}



public int MenuHandler_SilencePlayerList(Handle menu, MenuAction action, int param1, int param2)
{
	if(action == MenuAction_End)
		CloseHandle(menu);
		
	else if(action == MenuAction_Cancel)
	{
		if(param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
			DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Select)
	{
		char state_[128];
		GetMenuItem(menu, param2, state_, sizeof(state_));
		DisplaySilenceTimeMenu(param1, state_);
	}
}

void DisplaySilenceTimeMenu(int client, const char[] state_) {
	Handle menu = CreateMenu(MenuHandler_SilenceTimeList);
	SetMenuTitle(menu, "Silence disconnected player");
	SetMenuExitBackButton(menu, true);
	AddMenuItemWithState(menu, state_, "0", "Permanent");
	AddMenuItemWithState(menu, state_, "5", "5 Minutes");
	AddMenuItemWithState(menu, state_, "10", "10 Minutes");
	AddMenuItemWithState(menu, state_, "30", "30 Minutes");
	AddMenuItemWithState(menu, state_, "60", "1 Hour");
	AddMenuItemWithState(menu, state_, "120", "2 Hours");
	AddMenuItemWithState(menu, state_, "180", "3 Hours");
	AddMenuItemWithState(menu, state_, "240", "4 Hours");
	AddMenuItemWithState(menu, state_, "480", "8 Hours");
	AddMenuItemWithState(menu, state_, "720", "12 Hours");
	AddMenuItemWithState(menu, state_, "1440", "1 Day");
	AddMenuItemWithState(menu, state_, "4320", "3 Days");
	AddMenuItemWithState(menu, state_, "10080", "1 Week");
	AddMenuItemWithState(menu, state_, "20160", "2 Weeks");
	AddMenuItemWithState(menu, state_, "30240", "3 Weeks");
	AddMenuItemWithState(menu, state_, "43200", "1 Month");
	AddMenuItemWithState(menu, state_, "129600", "3 Months");
	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}



public int MenuHandler_SilenceTimeList(Handle menu, MenuAction action, int param1, int param2) {
	if(action == MenuAction_End)
		CloseHandle(menu);
	else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
			DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Select) {
		char state_[128];
		GetMenuItem(menu, param2, state_, sizeof(state_));
		DisplaySilenceReasonMenu(param1, state_);
	}
}



void DisplaySilenceReasonMenu(int client, const char[] state_)
{
	Handle menu = CreateMenu(MenuHandler_SilenceReasonList);
	SetMenuTitle(menu, "Silence reason");
	SetMenuExitBackButton(menu, true);
	
	int size = GetArraySize(Array_Reasons);
	
	for(int i=0;i < size;i++)
	{
		char Reason[128];
		Array_Reasons.GetString(i, Reason, sizeof(Reason));
		
		AddMenuItemWithState(menu, state_, Reason, Reason);
	}

	DisplayMenu(menu, client, MENU_TIME_FOREVER);
}



public int MenuHandler_SilenceReasonList(Handle menu, MenuAction action, int param1, int param2) {
	if(action == MenuAction_End)
		CloseHandle(menu);
	else if(action == MenuAction_Cancel) {
		if(param2 == MenuCancel_ExitBack && hTopMenu != INVALID_HANDLE)
			DisplayTopMenu(hTopMenu, param1, TopMenuPosition_LastCategory);
	}
	else if(action == MenuAction_Select) {
		char state_[128], state_parts[4][32];
		GetMenuItem(menu, param2, state_, sizeof(state_));
		if(ExplodeString(state_, "\n", state_parts, sizeof(state_parts), sizeof(state_parts[])) != 3)
			SetFailState("Bug in menu handlers");
		else CheckAndPerformSilence(param1, state_parts[0], StringToInt(state_parts[1]), state_parts[2]);
	}
}