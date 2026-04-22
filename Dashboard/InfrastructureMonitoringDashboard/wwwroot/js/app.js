// ==== UI LOGIC ====

const tabButtons = document.querySelectorAll(".tab");
const sections = {
  ad: document.getElementById("section-ad"),
  cert: document.getElementById("section-cert"),
  dns: document.getElementById("section-dns"),
  srv: document.getElementById("section-srv"),
  sql: document.getElementById("section-sql"),
  m365: document.getElementById("section-m365"),
  bkp: document.getElementById("section-bkp"),
  sw: document.getElementById("section-sw")
};

tabButtons.forEach(btn => {
  btn.addEventListener("click", () => {
    const key = btn.dataset.section;
    tabButtons.forEach(b => b.classList.remove("tab-active"));
    btn.classList.add("tab-active");
    Object.keys(sections).forEach(k => {
      sections[k].classList.toggle("section-active", k === key);
    });
  });
});

// Default date filters use the last 24 hours
const dateFromPicker = document.getElementById("dateFromPicker");
const dateToPicker = document.getElementById("dateToPicker");
const today = new Date();
const yesterday = new Date(today);
yesterday.setDate(yesterday.getDate() - 1);

dateFromPicker.value = yesterday.toISOString().slice(0, 10);
dateToPicker.value = today.toISOString().slice(0, 10);

const serverFilterSelect = document.getElementById("serverFilter");
const refreshBtn = document.getElementById("refreshBtn");

// Summary cards
const cardAgents = document.getElementById("cardAgents");
const cardAgentsRunning = document.getElementById("cardAgentsRunning");
const cardAdChanges = document.getElementById("cardAdChanges");
const cardAdGroups = document.getElementById("cardAdGroups");
const cardDnsChanges = document.getElementById("cardDnsChanges");
const cardDnsZones = document.getElementById("cardDnsZones");
const cardLicCost = document.getElementById("cardLicCost");
const cardLicDepts = document.getElementById("cardLicDepts");

// Bodies
const adGroupsBody = document.getElementById("adGroupsBody");
const groupPolicyBody = document.getElementById("groupPolicyBody");
const adCertsBody = document.getElementById("adCertsBody");
const dnsCreatedBody = document.getElementById("dnsCreatedBody");
const dnsDeletedBody = document.getElementById("dnsDeletedBody");
const srvRebootsBody = document.getElementById("srvRebootsBody");
const srvStatusBody = document.getElementById("srvStatusBody");
const sqlAgentStatusBody1 = document.getElementById("sqlAgentStatusBody1");
const sqlAgentStatusBody2 = document.getElementById("sqlAgentStatusBody2");
const cardDnsRecords = document.getElementById("cardDnsRecords");
const sqlJobsBody = document.getElementById("sqlJobsBody");
const m365LicBody = document.getElementById("m365LicBody");
const m365UnusedBody = document.getElementById("m365UnusedBody");
const m365LicSearch = document.getElementById("m365LicSearch");

// State for M365 license cost sorting
let m365LicSortColumn = "totalCost";
let m365LicSortDirection = "desc";
let m365LicAllData = [];

// Columns hidden in the license cost by department table
const hiddenColumns = [
  "F1", "F1_FIRSTLINE", "M365_F1", "MICROSOFT_365_F1", "O365_F1", "O365_STANDARD",
  "OFFICE_365_F1", "OFFICESUBSCRIPTION", "POWER_BI_PREMIUM_PER_USER", "SPB", "SPE_F1",
  "TEAMS_ESSENTIALS", "TEAMS_PREMIUM"
];
const backupBody = document.getElementById("backupBody");
const swAuditBody = document.getElementById("swAuditBody");

function formatDateTime(str) {
  if (!str) return "";
  const d = new Date(str);
  if (isNaN(d)) return str;
  return d.toLocaleString("en-US");
}

function getDateParams() {
  const dateFrom = dateFromPicker.value;
  const dateTo = dateToPicker.value;
  return { dateFrom, dateTo };
}

function buildUrl(baseUrl, params = {}) {
  const { dateFrom, dateTo } = getDateParams();
  const selectedServer = serverFilterSelect.value;
  
  const urlParams = new URLSearchParams();
  if (dateFrom) urlParams.append("dateFrom", dateFrom);
  if (dateTo) urlParams.append("dateTo", dateTo);
  if (selectedServer) urlParams.append("server", selectedServer);
  
  Object.keys(params).forEach(key => {
    if (params[key] !== undefined && params[key] !== null) {
      urlParams.append(key, params[key]);
    }
  });
  
  return `${baseUrl}?${urlParams.toString()}`;
}

// ==== RENDER FUNCTIONS ====

// Helper function to parse DN and extract CN name
function parseCN(dn) {
  if (!dn) return "";
  
  // Extract CN from DN
  // Example: "CN=Anton Kolobov,OU=Users,OU=InternalGroup,..." -> "Anton Kolobov"
  // Example: "cn=Mykyta Biletskyi" -> "Mykyta Biletskyi"
  if (dn.match(/^CN=/i)) {
    const match = dn.match(/^CN=([^,]+)/i);
    return match ? match[1] : dn;
  } else if (dn.match(/^cn=/i)) {
    const match = dn.match(/^cn=([^,]+)/i);
    return match ? match[1] : dn;
  }
  
  // If no CN prefix, return as is (might be just a name)
  return dn;
}

// Helper function to parse DN and extract first OU
function parseFirstOU(dn) {
  if (!dn) return "";
  
  // Extract first OU from DN
  // Example: "CN=Anton Kolobov,OU=Users,OU=InternalGroup,..." -> "Users"
  // Example: "OU=Internal IT,OU=CoreServices,..." -> "Internal IT"
  const match = dn.match(/OU=([^,]+)/i);
  return match ? match[1] : "";
}

// Helper function to check if string is a SID
function isSID(str) {
  if (!str) return false;
  // SID format: S-1-5-21-...
  return /^S-\d+-\d+(-\d+)+$/.test(str);
}

function renderAdGroups(data) {
  adGroupsBody.innerHTML = "";
  if (!data || data.length === 0) {
    adGroupsBody.innerHTML = "<tr><td colspan='7' class='muted'>No data</td></tr>";
    if (cardAdChanges) cardAdChanges.textContent = "0";
    if (cardAdGroups) cardAdGroups.textContent = "0 groups";
    return;
  }

  const groupsSet = new Set();
  // Limit to 10 rows for display
  const displayData = data.slice(0, 10);
  displayData.forEach(row => {
    const tr = document.createElement("tr");
    
    tr.appendChild(createCell(formatDateTime(row.time)));
    
    // Format action based on event type
    let actionText = row.action || "";
    const group = row.group || "";
    const member = row.member || "";
    const memberType = row.memberType || "";
    
    // Determine event type
    if (group === "SYSTEM" && memberType === "User") {
      // User created/deleted
      actionText = actionText === "Created" ? "User created" : 
                   actionText === "Deleted" ? "User deleted" : actionText;
    } else if (member === "SYSTEM" && memberType === "Group") {
      // Group created/deleted
      actionText = actionText === "Created" ? "Group created" : 
                   actionText === "Deleted" ? "Group deleted" : actionText;
    } else if (actionText === "Add") {
      actionText = "Added to group";
    } else if (actionText === "Remove") {
      actionText = "Removed from group";
    }
    
    tr.appendChild(createCell(actionText));
    
    // User column: show name from group column (parse CN from group DN)
    // If group is a DN, extract CN; if it's just a name, use it as is
    let userDisplay = "";
    if (group && group !== "SYSTEM") {
      // Extract CN from group DN or use group name if it's not a DN
      if (group.match(/^CN=/i) || group.includes("OU=")) {
        userDisplay = parseCN(group);
      } else {
        // If group is already a simple name (like "Chadley Swart"), use it
        userDisplay = group;
      }
    } else if (group === "SYSTEM" && memberType === "User") {
      // User created/deleted - member contains user name
      if (isSID(member)) {
        userDisplay = ""; // Don't show SID
      } else {
        userDisplay = parseCN(member);
      }
    }
    // User column - green color
    const userCell = createCell(userDisplay);
    userCell.style.color = "#00aa00"; // green
    userCell.style.fontWeight = "bold";
    tr.appendChild(userCell);
    
    // Group column: show first OU from group DN
    let groupDisplay = "";
    if (group && group !== "SYSTEM") {
      // Extract first OU from group DN
      if (group.includes("OU=")) {
        groupDisplay = parseFirstOU(group);
      } else {
        // If group doesn't have OU structure, leave empty or use a default
        groupDisplay = "";
      }
      if (groupDisplay) {
        groupsSet.add(groupDisplay);
      }
    } else if (member === "SYSTEM" && memberType === "Group") {
      // Group created/deleted - extract first OU from group
      groupDisplay = parseFirstOU(group);
    }
    tr.appendChild(createCell(groupDisplay));
    
    tr.appendChild(createCell(memberType));
    
    // Who column: show who performed the action (from row.by)
    tr.appendChild(createCell(row.by || row.performedBy || ""));
    
    tr.appendChild(createCell(row.dc || ""));
    
    adGroupsBody.appendChild(tr);
  });

  if (cardAdChanges) cardAdChanges.textContent = data.length.toString();
  if (cardAdGroups) cardAdGroups.textContent = `${groupsSet.size} groups`;
}

function renderAdCerts(data) {
  adCertsBody.innerHTML = "";
  if (!data || data.length === 0) {
    adCertsBody.innerHTML = "<tr><td colspan='5' class='muted'>No data</td></tr>";
    return;
  }

  // Sort by expiration date (soonest first)
  const sortedData = [...data].sort((a, b) => {
    const dateA = new Date(a.expires);
    const dateB = new Date(b.expires);
    return dateA - dateB;
  });

  // Limit to 5 rows for display
  const displayData = sortedData.slice(0, 5);

  displayData.forEach(row => {
    const tr = document.createElement("tr");
    
    // Color row based on severity
    if (row.severity === "red") {
      tr.style.backgroundColor = "rgba(239, 68, 68, 0.1)";
    } else if (row.severity === "yellow") {
      tr.style.backgroundColor = "rgba(234, 179, 8, 0.1)";
    } else {
      tr.style.backgroundColor = "rgba(34, 197, 94, 0.1)";
    }
    
    tr.appendChild(createCell(row.server));
    tr.appendChild(createCell(row.cert));
    tr.appendChild(createCell(formatDateTime(row.expires)));
    
    const tdDays = createCell(row.days.toString());
    if (row.severity === "red") {
      tdDays.style.color = "var(--red)";
      tdDays.style.fontWeight = "bold";
    } else if (row.severity === "yellow") {
      tdDays.style.color = "var(--yellow)";
    } else {
      tdDays.style.color = "var(--green)";
    }
    tr.appendChild(tdDays);
    
    const tdLevel = createCell("");
    let text = "";
    if (row.severity === "green") text = "OK";
    else if (row.severity === "yellow") text = "31–60";
    else if (row.severity === "red") text = "<= 30";
    tdLevel.textContent = text;
    if (row.severity === "red") tdLevel.className = "status-failed";
    else if (row.severity === "yellow") tdLevel.className = "status-warning";
    else tdLevel.className = "status-success";
    tr.appendChild(tdLevel);
    
    adCertsBody.appendChild(tr);
  });
}

function renderGroupPolicyEvents(data) {
  const groupPolicyBody = document.getElementById("groupPolicyBody");
  if (!groupPolicyBody) return;
  
  groupPolicyBody.innerHTML = "";
  if (!data || data.length === 0) {
    groupPolicyBody.innerHTML = "<tr><td colspan='6' class='muted'>No data</td></tr>";
    return;
  }

  data.forEach(row => {
    const tr = document.createElement("tr");
    tr.appendChild(createCell(formatDateTime(row.time)));
    
    const actionCell = createCell(row.action);
    if (row.action === "Created") {
      actionCell.className = "status-success";
    } else if (row.action === "Deleted") {
      actionCell.className = "status-failed";
    } else if (row.action === "Modified") {
      actionCell.className = "status-warning";
    }
    tr.appendChild(actionCell);
    
    tr.appendChild(createCell(row.gpoName));
    tr.appendChild(createCell(row.gpoGuid || ""));
    tr.appendChild(createCell(row.by || ""));
    tr.appendChild(createCell(row.dc));
    
    groupPolicyBody.appendChild(tr);
  });
}

function renderLdapUsers(data) {
  const ldapUsersBody = document.getElementById("ldapUsersBody");
  if (!ldapUsersBody) return;
  
  ldapUsersBody.innerHTML = "";
  if (!data || data.length === 0) {
    ldapUsersBody.innerHTML = "<tr><td colspan='3' class='muted'>No data</td></tr>";
    return;
  }

  // Limit to 5 rows for display
  const displayData = data.slice(0, 5);

  displayData.forEach(row => {
    const tr = document.createElement("tr");
    tr.appendChild(createCell(formatDateTime(row.date)));
    tr.appendChild(createCell(row.user));
    tr.appendChild(createCell(row.ip));
    ldapUsersBody.appendChild(tr);
  });
}

function renderDnsData(zonesData, recordsData) {
  dnsCreatedBody.innerHTML = "";
  dnsDeletedBody.innerHTML = "";
  
  const created = [];
  const deleted = [];
  const zones = new Set();
  
  // Process zones
  if (zonesData && Array.isArray(zonesData)) {
    zonesData.forEach(row => {
      const zoneName = row.zone || row.zoneName || "";
      if (zoneName) zones.add(zoneName);
      
      const action = (row.action || "").toLowerCase();
      const eventType = action.includes("created") || action.includes("added") ? "created" : 
                       action.includes("deleted") || action.includes("removed") ? "deleted" : null;
      
      if (eventType === "created") {
        created.push({
          time: row.time,
          event: "Zone created",
          name: zoneName || "N/A",
          user: row.user || row.performedBy || "",
          message: row.message || ""
        });
      } else if (eventType === "deleted") {
        deleted.push({
          time: row.time,
          event: "Zone deleted",
          name: zoneName || "N/A",
          user: row.user || row.performedBy || "",
          message: row.message || ""
        });
      }
    });
  }
  
  // Process records
  if (recordsData && Array.isArray(recordsData)) {
    recordsData.forEach(row => {
      // For records, we need RecordName (the full DNS name like qwerty.app.example.com)
      // NOT ZoneName (which is the zone like "app.example.com")
      const recordName = row.record || row.recordName || "";
      const zoneName = row.zone || row.zoneName || "";
      if (zoneName) zones.add(zoneName);
      
      // Use RecordName for display - this is the full DNS name
      const displayName = recordName || "N/A";
      
      const action = (row.action || row.operation || "").toLowerCase();
      const eventType = action.includes("created") || action.includes("added") ? "created" : 
                       action.includes("deleted") || action.includes("removed") ? "deleted" : null;
      
      if (eventType === "created") {
        created.push({
          time: row.time,
          event: "Record created",
          name: displayName,
          user: row.user || row.performedBy || "",
          message: row.message || ""
        });
      } else if (eventType === "deleted") {
        deleted.push({
          time: row.time,
          event: "Record deleted",
          name: displayName,
          user: row.user || row.performedBy || "",
          message: row.message || ""
        });
      }
    });
  }
  
  // Sort by time (newest first)
  created.sort((a, b) => new Date(b.time) - new Date(a.time));
  deleted.sort((a, b) => new Date(b.time) - new Date(a.time));
  
  // Render created
  if (created.length === 0) {
    dnsCreatedBody.innerHTML = "<tr><td colspan='5' class='muted'>No data</td></tr>";
  } else {
    created.forEach(item => {
      const tr = document.createElement("tr");
      const timeStr = formatDateTime(item.time);
      // Extract only time part (HH:mm:ss)
      const timeOnly = timeStr.includes(" ") ? timeStr.split(" ")[1] : timeStr;
      tr.appendChild(createCell(timeOnly));
      tr.appendChild(createCell(item.event));
      // Name column - green color for created items
      const nameCell = createCell(item.name);
      nameCell.style.color = "#00aa00"; // green
      nameCell.style.fontWeight = "bold";
      tr.appendChild(nameCell);
      tr.appendChild(createCell(item.user));
      tr.appendChild(createCell(item.message || ""));
      dnsCreatedBody.appendChild(tr);
    });
  }
  
  // Render deleted
  if (deleted.length === 0) {
    dnsDeletedBody.innerHTML = "<tr><td colspan='5' class='muted'>No data</td></tr>";
  } else {
    deleted.forEach(item => {
      const tr = document.createElement("tr");
      const timeStr = formatDateTime(item.time);
      // Extract only time part (HH:mm:ss)
      const timeOnly = timeStr.includes(" ") ? timeStr.split(" ")[1] : timeStr;
      tr.appendChild(createCell(timeOnly));
      tr.appendChild(createCell(item.event));
      // Name column - red color for deleted items
      const nameCell = createCell(item.name);
      nameCell.style.color = "#ff4444"; // red
      nameCell.style.fontWeight = "bold";
      tr.appendChild(nameCell);
      tr.appendChild(createCell(item.user));
      tr.appendChild(createCell(item.message || ""));
      dnsDeletedBody.appendChild(tr);
    });
  }
  
  // Update cards
  const totalChanges = created.length + deleted.length;
  if (cardDnsChanges) cardDnsChanges.textContent = totalChanges.toString();
  if (cardDnsRecords) cardDnsRecords.textContent = `${created.length + deleted.length} records`;
  if (cardDnsZones) cardDnsZones.textContent = `${zones.size} zones`;
}

function renderSrvReboots(data) {
  srvRebootsBody.innerHTML = "";
  if (!data || data.length === 0) {
    srvRebootsBody.innerHTML = "<tr><td colspan='5' class='muted'>No data</td></tr>";
    console.log("renderSrvReboots: No data to render");
    return;
  }

  console.log("renderSrvReboots: Rendering", data.length, "records");
  const selectedServer = serverFilterSelect.value;
  const filtered = selectedServer ? data.filter(x => x.server === selectedServer) : data;
  
  console.log("renderSrvReboots: Filtered to", filtered.length, "records (selected server:", selectedServer || "all", ")");

  if (filtered.length === 0) {
    srvRebootsBody.innerHTML = "<tr><td colspan='5' class='muted'>No data for the selected server</td></tr>";
    return;
  }

  filtered.forEach(row => {
    const tr = document.createElement("tr");
    tr.appendChild(createCell(row.server));
    tr.appendChild(createCell(formatDateTime(row.boot)));
    // Reboot time is inferred from the recorded shutdown time
    tr.appendChild(createCell(row.shutdown ? formatDateTime(row.shutdown) : ""));
    tr.appendChild(createCell(row.reason || ""));
    tr.appendChild(createCell(row.by || ""));
    srvRebootsBody.appendChild(tr);
  });
}

function renderSrvStatus(firewallData, otherData) {
  srvStatusBody.innerHTML = "";
  
  const firewallByServer = {};
  const servicesByServer = {}; // Zabbix, Wazuh, Qualys
  
  if (firewallData && Array.isArray(firewallData)) {
    firewallData.forEach(item => {
      if (!firewallByServer[item.serverName]) {
        firewallByServer[item.serverName] = {
          profiles: [],
          latestCaptureTime: null
        };
        servicesByServer[item.serverName] = {
          zabbix: null,
          wazuh: null,
          qualys: null,
          latestCaptureTime: null
        };
      }
      
      // Check if it's a service (Zabbix, Wazuh, Qualys) or firewall profile
      if (item.profile === "Zabbix" || item.profile === "Wazuh" || item.profile === "Qualys") {
        servicesByServer[item.serverName][item.profile.toLowerCase()] = item.state;
      } else {
        // Firewall profile
        firewallByServer[item.serverName].profiles.push({
          profile: item.profile,
          state: item.state
        });
      }
      
      // Update latest capture time
      const captureTime = new Date(item.captureTime);
      if (!firewallByServer[item.serverName].latestCaptureTime || 
          captureTime > new Date(firewallByServer[item.serverName].latestCaptureTime)) {
        firewallByServer[item.serverName].latestCaptureTime = item.captureTime;
      }
      if (!servicesByServer[item.serverName].latestCaptureTime || 
          captureTime > new Date(servicesByServer[item.serverName].latestCaptureTime)) {
        servicesByServer[item.serverName].latestCaptureTime = item.captureTime;
      }
    });
  }
  
  const allServers = new Set();
  Object.keys(firewallByServer).forEach(s => allServers.add(s));
  Object.keys(servicesByServer).forEach(s => allServers.add(s));
  if (otherData && Array.isArray(otherData)) {
    otherData.forEach(s => allServers.add(s.server));
  }
  
  const selectedServer = serverFilterSelect.value;
  const serversList = Array.from(allServers)
    .filter(s => !selectedServer || s === selectedServer)
    .sort();
  
  if (serversList.length === 0) {
    srvStatusBody.innerHTML = "<tr><td colspan='6' class='muted'>No data</td></tr>";
    return;
  }
  
  serversList.forEach(serverName => {
    const tr = document.createElement("tr");
    tr.appendChild(createCell(serverName));
    
    // Firewall
    const tdFw = createCell("");
    if (firewallByServer[serverName]) {
      const fwInfo = firewallByServer[serverName];
      const profiles = fwInfo.profiles;
      const domainProfile = profiles.find(p => p.profile === "Domain");
      const privateProfile = profiles.find(p => p.profile === "Private");
      const publicProfile = profiles.find(p => p.profile === "Public");
      
      let fwText = "";
      if (domainProfile) fwText += `Domain: ${domainProfile.state}`;
      if (privateProfile) fwText += (fwText ? ", " : "") + `Private: ${privateProfile.state}`;
      if (publicProfile) fwText += (fwText ? ", " : "") + `Public: ${publicProfile.state}`;
      
      if (!fwText) fwText = "N/A";
      tdFw.textContent = fwText;
      
      if (profiles.some(p => p.state === "Disabled")) {
        tdFw.className = "status-failed";
      } else if (profiles.some(p => p.state === "Enabled")) {
        tdFw.className = "status-success";
      }
    } else {
      tdFw.textContent = "N/A";
      tdFw.className = "muted";
    }
    tr.appendChild(tdFw);
    
    // Zabbix
    const services = servicesByServer[serverName] || {};
    const tdZabbix = createCell(services.zabbix || "N/A");
    if (services.zabbix === "Running") tdZabbix.className = "status-success";
    else if (services.zabbix === "Stopped") tdZabbix.className = "status-failed";
    else if (services.zabbix === "NotInstalled") tdZabbix.className = "muted";
    tr.appendChild(tdZabbix);
    
    // Wazuh
    const tdWazuh = createCell(services.wazuh || "N/A");
    if (services.wazuh === "Running") tdWazuh.className = "status-success";
    else if (services.wazuh === "Stopped") tdWazuh.className = "status-failed";
    else if (services.wazuh === "NotInstalled") tdWazuh.className = "muted";
    tr.appendChild(tdWazuh);
    
    // Qualys
    const tdQualys = createCell(services.qualys || "N/A");
    if (services.qualys === "Running") tdQualys.className = "status-success";
    else if (services.qualys === "Stopped") tdQualys.className = "status-failed";
    else if (services.qualys === "NotInstalled") tdQualys.className = "muted";
    tr.appendChild(tdQualys);
    
    // Last checked
    const tdChk = createCell("");
    const latestTime = firewallByServer[serverName]?.latestCaptureTime || 
                       servicesByServer[serverName]?.latestCaptureTime;
    if (latestTime) {
      tdChk.textContent = formatDateTime(latestTime);
    } else {
      tdChk.textContent = "N/A";
      tdChk.className = "muted";
    }
    tr.appendChild(tdChk);
    
    srvStatusBody.appendChild(tr);
  });
}

function renderSqlAgentStatus(data) {
  sqlAgentStatusBody1.innerHTML = "";
  sqlAgentStatusBody2.innerHTML = "";
  if (!data || data.length === 0) {
    sqlAgentStatusBody1.innerHTML = "<tr><td colspan='3' class='muted'>No data</td></tr>";
    return;
  }

  const agentRunning = data.filter(x => x.agentStatus === "Running").length;
  const half = Math.ceil(data.length / 2);
  const firstHalf = data.slice(0, half);
  const secondHalf = data.slice(half);
  
  firstHalf.forEach(row => {
    const tr = document.createElement("tr");
    tr.appendChild(createCell(row.serverName));
    
    const tdAgent = createCell(row.agentStatus || "");
    const agentOk = row.agentStatus === "Running";
    tdAgent.className = agentOk ? "agent-ok" : "agent-bad";
    tr.appendChild(tdAgent);
    
    tr.appendChild(createCell(formatDateTime(row.captureTime)));
    sqlAgentStatusBody1.appendChild(tr);
  });

  secondHalf.forEach(row => {
    const tr = document.createElement("tr");
    tr.appendChild(createCell(row.serverName));
    
    const tdAgent = createCell(row.agentStatus || "");
    const agentOk = row.agentStatus === "Running";
    tdAgent.className = agentOk ? "agent-ok" : "agent-bad";
    tr.appendChild(tdAgent);
    
    tr.appendChild(createCell(formatDateTime(row.captureTime)));
    sqlAgentStatusBody2.appendChild(tr);
  });

  if (cardAgents) {
    cardAgents.textContent = data.length > 0
      ? `${agentRunning} / ${data.length}`
      : "–";
  }
  if (cardAgentsRunning) {
    cardAgentsRunning.textContent = `${agentRunning} Running`;
  }
}

function renderSqlJobs(data) {
  sqlJobsBody.innerHTML = "";
  if (!data || data.length === 0) {
    sqlJobsBody.innerHTML = "<tr><td colspan='6' class='muted'>No data</td></tr>";
    return;
  }

  const selectedServer = serverFilterSelect.value;
  const filtered = selectedServer ? data.filter(x => x.serverName === selectedServer) : data;

  filtered.forEach(row => {
    const tr = document.createElement("tr");
    tr.appendChild(createCell(formatDateTime(row.captureTime)));
    tr.appendChild(createCell(row.serverName));
    tr.appendChild(createCell(row.jobName));
    
    const tdStatus = createCell(row.lastStatus || "");
    if (row.lastStatus === "Failed") {
      tdStatus.className = "status-failed";
    } else if (row.lastStatus === "Succeeded") {
      tdStatus.className = "status-success";
    } else {
      tdStatus.className = "status-warning";
    }
    tr.appendChild(tdStatus);
    
    tr.appendChild(createCell(formatDateTime(row.lastRunTime)));
    tr.appendChild(createCell(row.message || ""));
    sqlJobsBody.appendChild(tr);
  });
}

function renderM365Lic(data) {
  // Cache all data for filtering and sorting
  m365LicAllData = data || [];
  
  // Refresh sort indicators
  updateM365LicSortHeaders();
  
  // Apply filtering and sorting
  applyM365LicFilterAndSort();
}

function applyM365LicFilterAndSort() {
  m365LicBody.innerHTML = "";
  
  if (!m365LicAllData || m365LicAllData.length === 0) {
    m365LicBody.innerHTML = "<tr><td colspan='23' class='muted'>No data</td></tr>";
    const totalCostElement = document.getElementById("m365LicTotalCost");
    if (totalCostElement) totalCostElement.textContent = "0.00";
    return;
  }

  // Filter by the search query
  let filteredData = m365LicAllData;
  if (m365LicSearch && m365LicSearch.value.trim()) {
    const searchTerm = m365LicSearch.value.trim().toLowerCase();
    filteredData = m365LicAllData.filter(row => {
      const department = (row.department || "").toLowerCase();
      return department.includes(searchTerm);
    });
  }

  if (filteredData.length === 0) {
    m365LicBody.innerHTML = "<tr><td colspan='23' class='muted'>No results for the current query</td></tr>";
    const totalCostElement = document.getElementById("m365LicTotalCost");
    if (totalCostElement) totalCostElement.textContent = "0.00";
    return;
  }

  // Sorting
  const sortedData = [...filteredData].sort((a, b) => {
    let aVal, bVal;
    
    if (m365LicSortColumn === "department") {
      aVal = (a.department || "").toLowerCase();
      bVal = (b.department || "").toLowerCase();
      return m365LicSortDirection === "asc" ? 
        (aVal > bVal ? 1 : aVal < bVal ? -1 : 0) :
        (aVal < bVal ? 1 : aVal > bVal ? -1 : 0);
    } else if (m365LicSortColumn === "totalCost") {
      aVal = parseFloat(a.totalCost) || 0;
      bVal = parseFloat(b.totalCost) || 0;
      return m365LicSortDirection === "asc" ? aVal - bVal : bVal - aVal;
    } else if (m365LicSortColumn === "copilot") {
      // COPILOT is calculated as the sum of M365_COPILOT, COPILOT_STANDARD, and Microsoft_365_Copilot
      aVal = (parseInt(a.m365_copilot) || 0) + (parseInt(a.copilot_standard) || 0) + (parseInt(a.microsoft_365_copilot) || 0);
      bVal = (parseInt(b.m365_copilot) || 0) + (parseInt(b.copilot_standard) || 0) + (parseInt(b.microsoft_365_copilot) || 0);
      return m365LicSortDirection === "asc" ? aVal - bVal : bVal - aVal;
    } else {
      // License columns use numeric sorting
      aVal = parseInt(a[m365LicSortColumn]) || 0;
      bVal = parseInt(b[m365LicSortColumn]) || 0;
      return m365LicSortDirection === "asc" ? aVal - bVal : bVal - aVal;
    }
  });

  let totalCost = 0;
  
  // List of license columns excluding Department and TotalCost
  const licenseTypes = [
    "ENTERPRISEPACK", "F1", "F1_FIRSTLINE", "M365_F1", "M365_F1_COMM", "MICROSOFT_365_F1",
    "O365_BUSINESS", "O365_BUSINESS_ESSENTIALS", "O365_BUSINESS_PREMIUM", "O365_F1", "O365_STANDARD",
    "OFFICE_365_F1", "OFFICESUBSCRIPTION", "POWER_BI_PREMIUM_PER_USER", "POWER_BI_PRO",
    "SPB", "SPE_F1", "STANDARDPACK", "TEAMS_ESSENTIALS", "TEAMS_PREMIUM"
  ];

  sortedData.forEach(row => {
    const tr = document.createElement("tr");
    
    // Department
    tr.appendChild(createCell(row.department || ""));
    
    // TotalCost
    const totalCostValue = parseFloat(row.totalCost) || 0;
    totalCost += totalCostValue;
    tr.appendChild(createCell(totalCostValue.toFixed(2) + " €"));
    
    // Highlight license cells when values are greater than zero
    licenseTypes.forEach(licenseType => {
      const value = parseInt(row[licenseType.toLowerCase()]) || 0;
      const cell = createCell(value > 0 ? value.toString() : "");
      
      // Hide columns listed in hiddenColumns
      if (hiddenColumns.includes(licenseType)) {
        cell.style.display = "none";
      }
      
      if (value > 0) {
        cell.style.backgroundColor = "#00aa00"; // green
        cell.style.color = "#fff";
      }
      // Zero values remain blank
      
      tr.appendChild(cell);
    });
    
    // COPILOT is calculated as the sum of M365_COPILOT, COPILOT_STANDARD, and Microsoft_365_Copilot
    const copilotValue = (parseInt(row.m365_copilot) || 0) + 
                         (parseInt(row.copilot_standard) || 0) + 
                         (parseInt(row.microsoft_365_copilot) || 0);
    const copilotCell = createCell(copilotValue > 0 ? copilotValue.toString() : "");
    if (copilotValue > 0) {
      copilotCell.style.backgroundColor = "#00aa00"; // green
      copilotCell.style.color = "#fff";
    }
    tr.appendChild(copilotCell);
    
    m365LicBody.appendChild(tr);
  });

  // Update total cost
  const totalCostElement = document.getElementById("m365LicTotalCost");
  if (totalCostElement) {
    totalCostElement.textContent = totalCost.toFixed(2);
  }
  
  // Update daily M365 license cost using total cost divided by days in the current month
  const cardLicCostElement = document.getElementById("cardLicCost");
  if (cardLicCostElement && totalCost > 0) {
    const now = new Date();
    const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
    const costPerDay = totalCost / daysInMonth;
    cardLicCostElement.textContent = costPerDay.toFixed(2) + " €";
  } else if (cardLicCostElement) {
    cardLicCostElement.textContent = "–";
  }
}

function updateM365LicSortHeaders() {
  const headers = document.querySelectorAll("#section-m365 .table-wrapper thead th.sortable");
  headers.forEach(header => {
    const column = header.getAttribute("data-column");
    if (column === m365LicSortColumn) {
      const arrow = m365LicSortDirection === "asc" ? " ↑" : " ↓";
      header.textContent = header.textContent.replace(/ [↑↓↕]/, "") + arrow;
    } else {
      header.textContent = header.textContent.replace(/ [↑↓↕]/, "") + " ↕";
    }
  });
}

function renderM365Unused(data) {
  m365UnusedBody.innerHTML = "";
  if (!data || data.length === 0) {
    m365UnusedBody.innerHTML = "<tr><td colspan='6' class='muted'>No data</td></tr>";
    const totalCostElement = document.getElementById("m365UnusedTotalCost");
    if (totalCostElement) totalCostElement.textContent = "0.00";
    return;
  }

  let totalCost = 0;

  data.forEach(row => {
    const tr = document.createElement("tr");
    
    // Display Name
    tr.appendChild(createCell(row.displayName || ""));
    
    // User Principal Name
    tr.appendChild(createCell(row.userPrincipalName || ""));
    
    // Last Activity
    const lastActivityCell = createCell(row.lastActivity ? formatDateTime(row.lastActivity) : "Not found");
    tr.appendChild(lastActivityCell);
    
    // Days inactive with color coding
    const daysInactive = row.daysSinceLastActivity || 0;
    const daysCell = createCell(daysInactive > 0 ? daysInactive.toString() : "N/A");
    
    // Color coding: 30-60 days = yellow, 60-90 days = orange, 90+ days = red
    if (daysInactive >= 90) {
      daysCell.style.backgroundColor = "#ff4444"; // red
      daysCell.style.color = "#fff";
    } else if (daysInactive >= 60) {
      daysCell.style.backgroundColor = "#ff8800"; // orange
      daysCell.style.color = "#fff";
    } else if (daysInactive >= 30) {
      daysCell.style.backgroundColor = "#ffaa00"; // yellow
      daysCell.style.color = "#000";
    }
    tr.appendChild(daysCell);
    
    // Licenses
    tr.appendChild(createCell(row.licenses || ""));
    
    // Monthly Cost
    const monthlyCost = parseFloat(row.monthlyCost) || 0;
    totalCost += monthlyCost;
    tr.appendChild(createCell(monthlyCost.toFixed(2) + " €"));
    
    m365UnusedBody.appendChild(tr);
  });

  // Update total cost
  const totalCostElement = document.getElementById("m365UnusedTotalCost");
  if (totalCostElement) {
    totalCostElement.textContent = totalCost.toFixed(2);
  }
}

function renderBackup(data) {
  backupBody.innerHTML = "";
  if (!data || data.length === 0) {
    backupBody.innerHTML = "<tr><td colspan='6' class='muted'>No data</td></tr>";
    return;
  }

  data.forEach(row => {
    const tr = document.createElement("tr");
    tr.appendChild(createCell(row.server));
    tr.appendChild(createCell(row.db));
    tr.appendChild(createCell(formatDateTime(row.backupDate)));
    tr.appendChild(createCell(row.bucket));
    tr.appendChild(createCell(row.file));
    
    const tdUp = createCell(row.uploaded ? "Yes" : "No");
    tdUp.className = row.uploaded ? "status-success" : "status-failed";
    tr.appendChild(tdUp);
    
    backupBody.appendChild(tr);
  });
}

function renderSwAudit(data) {
  swAuditBody.innerHTML = "";
  if (!data || data.length === 0) {
    swAuditBody.innerHTML = "<tr><td colspan='4' class='muted'>No data</td></tr>";
    return;
  }

  // Function to filter and format roles (remove long technical names, keep only readable roles)
  function formatRoles(rolesArray) {
    if (!Array.isArray(rolesArray)) return "";
    
    // Filter out technical/feature names, keep only main roles
    const mainRoles = rolesArray.filter(role => {
      const roleLower = role.toLowerCase();
      // Skip technical features
      if (roleLower.includes("net-framework") || 
          roleLower.includes("net-wcf") ||
          roleLower.includes("powershell") ||
          roleLower.includes("windows-defender") ||
          roleLower.includes("xps-viewer") ||
          roleLower.includes("wow64") ||
          roleLower.includes("dataarchiver") ||
          roleLower.includes("admincenter") ||
          roleLower.includes("storage-services") ||
          roleLower.includes("fileandstorage") ||
          roleLower.length > 30) {
        return false;
      }
      return true;
    });
    
    // Format role names (remove dashes, capitalize)
    return mainRoles.map(role => {
      return role
        .replace(/-/g, " ")
        .replace(/\b\w/g, l => l.toUpperCase());
    }).join(", ");
  }

  data.forEach(row => {
    const tr = document.createElement("tr");
    // Use server name (should come from backend as ServerName)
    const serverName = row.server || row.serverName || "N/A";
    tr.appendChild(createCell(serverName));
    tr.appendChild(createCell(row.os || ""));
    tr.appendChild(createCell(formatRoles(row.roles)));
    tr.appendChild(createCell(formatDateTime(row.scanned)));
    swAuditBody.appendChild(tr);
  });
}

function createCell(text) {
  const td = document.createElement("td");
  td.textContent = text || "";
  return td;
}

function updateServerFilter(servers) {
  const uniqueServers = [...new Set(servers)].filter(x => !!x).sort();
  const current = serverFilterSelect.value;
  
  serverFilterSelect.innerHTML =
    `<option value="">All</option>` +
    uniqueServers.map(s => `<option value="${s}">${s}</option>`).join("");
  
  if (current && uniqueServers.includes(current)) {
    serverFilterSelect.value = current;
  }
}

// ==== API LOADERS ====

async function loadAdGroups() {
  try {
    const url = buildUrl("/api/ad-groups");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("AD API error:", data.error);
      adGroupsBody.innerHTML = `<tr><td colspan='7' class='muted'>Error: ${data.error}</td></tr>`;
      return;
    }
    if (Array.isArray(data)) {
      console.log("AD Groups loaded:", data.length);
      renderAdGroups(data);
    } else {
      console.error("AD Groups: unexpected data format", data);
      adGroupsBody.innerHTML = "<tr><td colspan='7' class='muted'>Invalid data format</td></tr>";
    }
  } catch (e) {
    console.error("Failed to load AD group changes:", e);
    adGroupsBody.innerHTML = "<tr><td colspan='7' class='muted'>Load error</td></tr>";
  }
}

async function loadDnsZones() {
  try {
    const url = buildUrl("/api/dns-zones");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("DNS zones API error:", data.error);
      return null;
    }
    if (Array.isArray(data)) {
      console.log("DNS Zones loaded:", data.length, data);
      return data;
    }
    console.error("DNS Zones: unexpected data format", data);
    return null;
  } catch (e) {
    console.error("Load error DNS zones:", e);
    return null;
  }
}

async function loadDnsRecords() {
  try {
    const url = buildUrl("/api/dns-records");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("DNS records API error:", data.error);
      return null;
    }
    if (Array.isArray(data)) {
      console.log("DNS Records loaded:", data.length, data);
      return data;
    }
    return null;
  } catch (e) {
    console.error("Load error DNS records:", e);
    return null;
  }
}

async function loadFirewallStatus() {
  try {
    const url = buildUrl("/api/firewall-status");
    const resp = await fetch(url);
    const data = await resp.json();
    return Array.isArray(data) ? data : null;
  } catch (e) {
    console.error("Failed to load firewall status:", e);
    return null;
  }
}

async function loadSqlAgentStatus() {
  try {
    const url = buildUrl("/api/sql-agent-status");
    const resp = await fetch(url);
    const data = await resp.json();
    if (Array.isArray(data)) {
      renderSqlAgentStatus(data);
      return data;
    }
    return null;
  } catch (e) {
    console.error("Failed to load SQL agent status:", e);
    sqlAgentStatusBody.innerHTML = "<tr><td colspan='3' class='muted'>Load error</td></tr>";
    return null;
  }
}

async function loadSqlJobs() {
  try {
    const url = buildUrl("/api/sql-jobs");
    const resp = await fetch(url);
    const data = await resp.json();
    if (Array.isArray(data)) {
      renderSqlJobs(data);
      return data;
    }
    return null;
  } catch (e) {
    console.error("Failed to load SQL jobs:", e);
    sqlJobsBody.innerHTML = "<tr><td colspan='6' class='muted'>Load error</td></tr>";
    return null;
  }
}

async function loadAdCertificates() {
  try {
    const url = buildUrl("/api/ad-certificates");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("AD certificates API error:", data.error);
      adCertsBody.innerHTML = `<tr><td colspan='5' class='muted'>Error: ${data.error}</td></tr>`;
      return null;
    }
    if (Array.isArray(data)) {
      console.log("AD Certificates loaded:", data.length);
      renderAdCerts(data);
      return data;
    } else {
      console.error("AD Certificates: unexpected data format", data);
      adCertsBody.innerHTML = "<tr><td colspan='5' class='muted'>Invalid data format</td></tr>";
      return null;
    }
  } catch (e) {
    console.error("Failed to load AD certificates:", e);
    adCertsBody.innerHTML = "<tr><td colspan='5' class='muted'>Load error</td></tr>";
    return null;
  }
}

function renderWebServerCerts(data) {
  const webServerCertsBody = document.getElementById("webServerCertsBody");
  if (!webServerCertsBody) return;
  
  webServerCertsBody.innerHTML = "";
  if (!data || data.length === 0) {
    webServerCertsBody.innerHTML = "<tr><td colspan='3' class='muted'>No data</td></tr>";
    return;
  }

  // Sort by expiration date (soonest first)
  const sortedData = [...data].sort((a, b) => {
    const dateA = new Date(a.expires);
    const dateB = new Date(b.expires);
    return dateA - dateB;
  });

  sortedData.forEach(row => {
    const tr = document.createElement("tr");
    
    // Color row based on severity
    if (row.severity === "red") {
      tr.style.backgroundColor = "rgba(239, 68, 68, 0.1)";
    } else if (row.severity === "yellow") {
      tr.style.backgroundColor = "rgba(234, 179, 8, 0.1)";
    } else {
      tr.style.backgroundColor = "rgba(34, 197, 94, 0.1)";
    }
    
    tr.appendChild(createCell(row.siteName));
    tr.appendChild(createCell(row.url));
    
    const tdDays = createCell(row.days.toString());
    if (row.severity === "red") {
      tdDays.style.color = "var(--red)";
      tdDays.style.fontWeight = "bold";
    } else if (row.severity === "yellow") {
      tdDays.style.color = "var(--yellow)";
    } else {
      tdDays.style.color = "var(--green)";
    }
    tr.appendChild(tdDays);
    
    webServerCertsBody.appendChild(tr);
  });
}

async function loadGroupPolicyEvents() {
  try {
    const url = buildUrl("/api/group-policy-events");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("Group Policy events API error:", data.error);
      const groupPolicyBody = document.getElementById("groupPolicyBody");
      if (groupPolicyBody) {
        groupPolicyBody.innerHTML = `<tr><td colspan='6' class='muted'>Error: ${data.error}</td></tr>`;
      }
      return null;
    }
    if (Array.isArray(data)) {
      console.log("Group Policy Events loaded:", data.length);
      renderGroupPolicyEvents(data);
      return data;
    } else {
      console.error("Group Policy Events: unexpected data format", data);
      const groupPolicyBody = document.getElementById("groupPolicyBody");
      if (groupPolicyBody) {
        groupPolicyBody.innerHTML = "<tr><td colspan='6' class='muted'>Invalid data format</td></tr>";
      }
      return null;
    }
  } catch (e) {
    console.error("Load error Group Policy events:", e);
    const groupPolicyBody = document.getElementById("groupPolicyBody");
    if (groupPolicyBody) {
      groupPolicyBody.innerHTML = "<tr><td colspan='6' class='muted'>Load error</td></tr>";
    }
    return null;
  }
}

async function loadWebServerCertificates() {
  try {
    const url = buildUrl("/api/web-server-certificates");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("Web server certificates API error:", data.error);
      const webServerCertsBody = document.getElementById("webServerCertsBody");
      if (webServerCertsBody) {
        webServerCertsBody.innerHTML = `<tr><td colspan='3' class='muted'>Error: ${data.error}</td></tr>`;
      }
      return null;
    }
    if (Array.isArray(data)) {
      console.log("Web Server Certificates loaded:", data.length);
      renderWebServerCerts(data);
      return data;
    } else {
      console.error("Web Server Certificates: unexpected data format", data);
      const webServerCertsBody = document.getElementById("webServerCertsBody");
      if (webServerCertsBody) {
        webServerCertsBody.innerHTML = "<tr><td colspan='3' class='muted'>Invalid data format</td></tr>";
      }
      return null;
    }
  } catch (e) {
    console.error("Failed to load web server certificates:", e);
    const webServerCertsBody = document.getElementById("webServerCertsBody");
    if (webServerCertsBody) {
      webServerCertsBody.innerHTML = "<tr><td colspan='3' class='muted'>Load error</td></tr>";
    }
    return null;
  }
}

async function loadLdapUsers() {
  try {
    const url = buildUrl("/api/ldap-users");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("LDAP users API error:", data.error);
      const ldapUsersBody = document.getElementById("ldapUsersBody");
      if (ldapUsersBody) {
        ldapUsersBody.innerHTML = `<tr><td colspan='3' class='muted'>Error: ${data.error}</td></tr>`;
      }
      return;
    }
    if (Array.isArray(data)) {
      console.log("LDAP Users loaded:", data.length);
      renderLdapUsers(data);
    } else {
      console.error("LDAP Users: unexpected data format", data);
      const ldapUsersBody = document.getElementById("ldapUsersBody");
      if (ldapUsersBody) {
        ldapUsersBody.innerHTML = "<tr><td colspan='3' class='muted'>Invalid data format</td></tr>";
      }
    }
  } catch (e) {
    console.error("Failed to load LDAP user activity:", e);
    const ldapUsersBody = document.getElementById("ldapUsersBody");
    if (ldapUsersBody) {
      ldapUsersBody.innerHTML = "<tr><td colspan='3' class='muted'>Load error</td></tr>";
    }
  }
}

async function loadServerSoftware() {
  try {
    const url = buildUrl("/api/server-software");
    const resp = await fetch(url);
    const data = await resp.json();
    if (Array.isArray(data)) {
      renderSwAudit(data);
      return data;
    }
    return null;
  } catch (e) {
    console.error("Failed to load installed software and roles:", e);
    swAuditBody.innerHTML = "<tr><td colspan='5' class='muted'>Load error</td></tr>";
    return null;
  }
}

async function loadServerReboots() {
  try {
    const url = buildUrl("/api/server-reboots");
    console.log("Loading server reboots from:", url);
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    console.log("Server Reboots API response:", data);
    if (data.error) {
      console.error("Server reboot API error:", data.error);
      return null;
    }
    if (Array.isArray(data)) {
      console.log("Server Reboots loaded:", data.length, "records");
      if (data.length > 0) {
        console.log("First record:", data[0]);
      }
      return data;
    } else {
      console.error("Server Reboots: unexpected data format", data);
      return null;
    }
  } catch (e) {
    console.error("Failed to load server reboot history:", e);
    return null;
  }
}

async function loadM365UnusedLicenses() {
  try {
    const url = buildUrl("/api/m365-unused-licenses");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("M365 inactive licenses API error:", data.error);
      return null;
    }
    if (Array.isArray(data)) {
      console.log("M365 Unused Licenses loaded:", data.length, "records");
      return data;
    } else {
      console.error("M365 Unused Licenses: unexpected data format", data);
      return null;
    }
  } catch (e) {
    console.error("Failed to load inactive M365 users:", e);
    return null;
  }
}

async function loadM365LicenseCostByDepartment() {
  try {
    const url = buildUrl("/api/m365-license-cost-by-department");
    const resp = await fetch(url);
    if (!resp.ok) {
      throw new Error(`HTTP ${resp.status}: ${resp.statusText}`);
    }
    const data = await resp.json();
    if (data.error) {
      console.error("M365 license cost by department API error:", data.error);
      return null;
    }
    if (Array.isArray(data)) {
      console.log("M365 License Cost by Department loaded:", data.length, "records");
      return data;
    } else {
      console.error("M365 License Cost by Department: unexpected data format", data);
      return null;
    }
  } catch (e) {
    console.error("Failed to load M365 license cost by department:", e);
    return null;
  }
}

// ==== MAIN LOAD FUNCTION ====

async function loadAll() {
  // Collect servers from all sources
  const allServers = new Set();
  
  // AD
  const adGroupsData = await loadAdGroups();
  if (adGroupsData && Array.isArray(adGroupsData)) {
    adGroupsData.forEach(row => {
      if (row.dc) allServers.add(row.dc);
    });
  }
  
  // DNS
  const dnsZonesData = await loadDnsZones();
  const dnsRecordsData = await loadDnsRecords();
  renderDnsData(dnsZonesData, dnsRecordsData);
  if (dnsZonesData && Array.isArray(dnsZonesData)) {
    dnsZonesData.forEach(row => {
      if (row.server) allServers.add(row.server);
    });
  }
  if (dnsRecordsData && Array.isArray(dnsRecordsData)) {
    dnsRecordsData.forEach(row => {
      if (row.server) allServers.add(row.server);
    });
  }
  
  // Servers
  const firewallData = await loadFirewallStatus();
  if (firewallData && Array.isArray(firewallData)) {
    renderSrvStatus(firewallData, []);
    firewallData.forEach(row => {
      if (row.server) allServers.add(row.server);
    });
  }
  
  // SQL
  const sqlAgentData = await loadSqlAgentStatus();
  if (sqlAgentData && Array.isArray(sqlAgentData)) {
    sqlAgentData.forEach(row => {
      if (row.server) allServers.add(row.server);
    });
  }
  
  const sqlJobsData = await loadSqlJobs();
  if (sqlJobsData && Array.isArray(sqlJobsData)) {
    renderSqlJobs(sqlJobsData);
    sqlJobsData.forEach(row => {
      if (row.serverName) allServers.add(row.serverName);
    });
  }
  
  // Software
  const softwareData = await loadServerSoftware();
  if (softwareData && Array.isArray(softwareData)) {
    softwareData.forEach(row => {
      if (row.server) allServers.add(row.server);
    });
  }
  
  // AD Certificates
  const adCertsData = await loadAdCertificates();
  if (adCertsData && Array.isArray(adCertsData)) {
    adCertsData.forEach(row => {
      if (row.server) allServers.add(row.server);
    });
  }
  
  // Group Policy Events
  await loadGroupPolicyEvents();
  
  // Web Server Certificates
  await loadWebServerCertificates();
  
  // LDAP Users
  await loadLdapUsers();
  
  // Server Reboots
  const rebootsData = await loadServerReboots();
  if (rebootsData && Array.isArray(rebootsData)) {
    console.log("Server Reboots data received:", rebootsData.length, "records");
    renderSrvReboots(rebootsData);
    rebootsData.forEach(row => {
      if (row.server) allServers.add(row.server);
    });
  } else {
    console.warn("Server Reboots: No data or invalid format", rebootsData);
    renderSrvReboots([]);
  }
  
  // M365 Unused Licenses
  const m365UnusedData = await loadM365UnusedLicenses();
  if (m365UnusedData && Array.isArray(m365UnusedData)) {
    renderM365Unused(m365UnusedData);
  } else {
    renderM365Unused([]);
  }
  
  // M365 License Cost by Department
  const m365LicData = await loadM365LicenseCostByDepartment();
  if (m365LicData && Array.isArray(m365LicData)) {
    renderM365Lic(m365LicData);
  } else {
    renderM365Lic([]);
  }
  
  // Update server filter with all collected servers
  updateServerFilter(Array.from(allServers));
  await loadBackupGcpBuckets();
}

refreshBtn.addEventListener("click", () => {
  loadAll();
});

serverFilterSelect.addEventListener("change", () => {
  loadAll();
});

dateFromPicker.addEventListener("change", () => {
  loadAll();
});

dateToPicker.addEventListener("change", () => {
  loadAll();
});

// Handlers for M365 license cost sorting and search
if (m365LicSearch) {
  m365LicSearch.addEventListener("input", () => {
    applyM365LicFilterAndSort();
  });
}

// Click handlers for sortable table headers
document.addEventListener("click", (e) => {
  if (e.target && e.target.classList.contains("sortable") && e.target.closest("#section-m365")) {
    const column = e.target.getAttribute("data-column");
    if (column) {
      if (m365LicSortColumn === column) {
        // Toggle sort direction
        m365LicSortDirection = m365LicSortDirection === "asc" ? "desc" : "asc";
      } else {
        // New column selected, sort descending by default
        m365LicSortColumn = column;
        m365LicSortDirection = "desc";
      }
      updateM365LicSortHeaders();
      applyM365LicFilterAndSort();
    }
  }
});

// Initial load
loadAll();

