var builder = WebApplication.CreateBuilder(args);
var app = builder.Build();

app.MapGet("/", () => "Late night testing for DBG Project - 061826");

app.Run();
